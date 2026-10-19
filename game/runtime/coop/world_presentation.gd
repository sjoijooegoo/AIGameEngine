extends RefCounted
## A bounded adaptive render buffer decouples snapshots from presentation.
## It never simulates AI, damage or door occupancy on a client.
const DELAY_TICKS := 6.0
var frames: Array=[]
var render_tick := 0.0
var world: Node3D
var samples := 0
var elapsed := 0.0
var last_arrival := -1.0
var delay_ticks := 6.0
var settled_poses: Dictionary={}
var hidden_skipped := 0
var corpse_skipped := 0

func reset() -> void:
	frames.clear();render_tick=0.0;samples=0;elapsed=0;last_arrival=-1;delay_ticks=6
	settled_poses.clear();hidden_skipped=0;corpse_skipped=0

func push(server_tick: int,packet: Dictionary) -> void:
	if last_arrival>=0:
		var desired:=clampf((elapsed-last_arrival)*75.0,6.0,15.0)
		delay_ticks=lerpf(delay_ticks,desired,.3 if desired>delay_ticks else .025)
	last_arrival=elapsed
	if frames.is_empty():render_tick=float(server_tick)-delay_ticks
	elif float(server_tick)-render_tick>60.0:render_tick=float(server_tick)-delay_ticks
	var actors: Dictionary={}
	for row in packet.enemies:actors[row[0]]=row
	frames.append({"tick":server_tick,"doors":packet.doors,"actors":actors})
	while frames.size()>12:frames.pop_front()

func advance(dt: float) -> void:
	elapsed+=dt
	if frames.is_empty():return
	var lag: float=float(frames[-1].tick)-render_tick
	var rate:=clampf(1.0+(lag-delay_ticks)*.015,.9,1.1)
	render_tick=minf(render_tick+dt*60.0*rate,float(frames[-1].tick)+6.0)
	while frames.size()>2 and float(frames[1].tick)<=render_tick:frames.pop_front()
	var a: Dictionary=frames[0];var b: Dictionary=frames[1] if frames.size()>1 else a
	var weight:=clampf((render_tick-float(a.tick))/maxf(1.0,float(b.tick-a.tick)),0.0,1.0)
	var extrapolate:=clampf((render_tick-float(b.tick))/60.0,0.0,.1)
	for id in b.doors:
		if not world.doors.has(id):continue
		var door=world.doors[id];var next: Array=b.doors[id];var previous: Array=a.doors.get(id,next)
		door.progress=lerpf(float(previous[0]),float(next[0]),weight)
		if extrapolate>0 and not next[3] and b.tick>a.tick:
			var speed: float=(float(next[0])-float(previous[0]))*60.0/float(b.tick-a.tick)
			door.progress=clampf(float(next[0])+speed*extrapolate,minf(next[0],next[1]),maxf(next[0],next[1]))
		door.apply_progress()
	for enemy in world.infected:
		var id:=str(enemy.name)
		if not b.actors.has(id):continue
		var next: Array=b.actors[id];var previous: Array=a.actors.get(id,next)
		if not enemy.active or not next[8]:
			hidden_skipped+=1;settled_poses.erase(id);continue
		if enemy.mode=="dead":
			if enemy.ragdoll.sleeping:corpse_skipped+=1
			else:enemy.ragdoll.corpse_stream.advance(enemy.ragdoll,dt)
			enemy.update_shadow_layers()
			continue # No root/joint snapshot may overwrite local corpse physics.
		if not previous[8]:previous=next # Reactivation must not lerp from a hidden fixture.
		var teleport: bool=Vector3(previous[1]).distance_squared_to(next[1])>16.0
		enemy.position=next[1] if teleport else Vector3(previous[1]).lerp(next[1],weight)
		if extrapolate>0 and next[5] in ["chase","patrol"]:enemy.position+=Vector3(next[3])*extrapolate
		enemy.rotation.y=lerp_angle(float(previous[2]),float(next[2]),weight)
		if enemy.mode!="dead":
			settled_poses.erase(id)
			# Gait is distance-driven. Never rewind its phase on every packet.
			if teleport:enemy.native_motion.previous_position=enemy.global_position
			enemy.clock+=dt;enemy.state_time+=dt;enemy.reaction_time+=dt
			enemy.play_pose(dt,enemy.global_position.distance_squared_to(world.player.global_position)<144.0)
	samples+=1

func observe() -> Dictionary:
	return {"buffer_ms":delay_ticks*1000.0/60.0,"extrapolate_max_ms":100,"render_tick":render_tick,"frames":frames.size(),"samples":samples,"world_snapshot_hz":10,"simulation_hz":60,"hidden_skipped":hidden_skipped,"corpse_skipped":corpse_skipped}

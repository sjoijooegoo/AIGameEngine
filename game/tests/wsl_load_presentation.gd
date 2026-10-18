extends "res://coop/world_presentation.gd"
## Load-generator-only presentation. Keeps snapshot buffering, door/actor
## interpolation and movement capsules; omits invisible bone animation work.
## Never installed on a server or exported to the playable game.
func advance(dt: float) -> void:
	elapsed += dt
	if frames.is_empty(): return
	var lag: float = float(frames[-1].tick)-render_tick
	var rate := clampf(1.0+(lag-delay_ticks)*.015,.9,1.1)
	render_tick = minf(render_tick+dt*60.0*rate,float(frames[-1].tick)+6.0)
	while frames.size()>2 and float(frames[1].tick)<=render_tick: frames.pop_front()
	var a: Dictionary=frames[0]
	var b: Dictionary=frames[1] if frames.size()>1 else a
	var weight:=clampf((render_tick-float(a.tick))/maxf(1.0,float(b.tick-a.tick)),0.0,1.0)
	var extrapolate:=clampf((render_tick-float(b.tick))/60.0,0.0,.1)
	for id in b.doors:
		if not world.doors.has(id): continue
		var door=world.doors[id]
		var next: Array=b.doors[id]
		var previous: Array=a.doors.get(id,next)
		door.progress=lerpf(float(previous[0]),float(next[0]),weight)
		if extrapolate>0 and not next[3] and b.tick>a.tick:
			var speed: float=(float(next[0])-float(previous[0]))*60.0/float(b.tick-a.tick)
			door.progress=clampf(float(next[0])+speed*extrapolate,minf(next[0],next[1]),maxf(next[0],next[1]))
		door.apply_progress()
	for enemy in world.infected:
		var id:=str(enemy.name)
		if not b.actors.has(id): continue
		var next: Array=b.actors[id]
		var previous: Array=a.actors.get(id,next)
		if not enemy.active or not next[8]: continue
		if not previous[8]: previous=next
		var teleport: bool=Vector3(previous[1]).distance_squared_to(next[1])>16.0
		enemy.position=next[1] if teleport else Vector3(previous[1]).lerp(next[1],weight)
		if extrapolate>0 and next[5] in ["chase","patrol"]: enemy.position+=Vector3(next[3])*extrapolate
		enemy.rotation.y=lerp_angle(float(previous[2]),float(next[2]),weight)
	samples+=1

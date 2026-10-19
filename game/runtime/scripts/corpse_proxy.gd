extends RefCounted
## One swept torso sphere, no joints, skinning or constraint iterations.
## Only the authority runs this; living-body impacts remain authoritative.
var index := -1
var offsets: Array[Vector3]=[]
var velocity := Vector3.ZERO
var fall_time := 0.0
var fall_axis := Vector3.RIGHT
var rotation := Basis.IDENTITY

func setup(body) -> void:
	var center: Vector3=(body.positions[body.ids.Pelvis]+body.positions[body.ids.Spine2])*.5
	for point: Vector3 in body.positions:offsets.append(point-center)
	velocity=((body.positions[body.ids.Pelvis]-body.previous[body.ids.Pelvis])+(body.positions[body.ids.Spine2]-body.previous[body.ids.Spine2]))*30.0
	var flat:=Vector3(velocity.x,0,velocity.z).normalized()
	if flat.length_squared()<.01:flat=body.actor.global_basis.z
	fall_axis=Vector3.UP.cross(flat).normalized()
	index=body.positions.size();body.add_point("AuthorityTorso",center,.28)

func wake(body) -> void:
	velocity=((body.positions[body.ids.Pelvis]-body.previous[body.ids.Pelvis])+(body.positions[body.ids.Spine2]-body.previous[body.ids.Spine2]))*30.0
	if body.launch_remaining>0:velocity=body.launch_velocity

func advance(body,dt: float) -> void:
	if dt<=0:body.update_hitboxes();return
	var before: Array[Vector3]=body.positions.duplicate()
	var center: Vector3=body.positions[index]
	body.age+=dt;fall_time+=dt;body.launch_remaining=maxf(0,body.launch_remaining-dt)
	body.frame_contacts=0;body.frame_wall_contact=false;body.frame_floor_contact=false
	var drag: float=float(body.actor.game.firearms.feedback_data.shotgun.air_drag) if body.launch_kind.begins_with("shotgun") and body.launch_remaining>0 else 1.7
	velocity=(velocity*exp(-dt*drag)+Vector3.DOWN*12*dt).limit_length(body.speed_limit())
	body.previous[index]=center;body.positions[index]=center+velocity*dt
	body.collide(index,center) # The same wall/floor sweeps, once per body.
	velocity=(body.positions[index]-body.previous[index])*60.0
	if body.frame_floor_contact:velocity*=.7
	if body.frame_wall_contact:body.launch_remaining=0
	rotation=Basis(fall_axis,smoothstep(0,.45,fall_time)*PI*.5)
	for i in offsets.size():
		body.previous[i]=before[i];body.positions[i]=body.positions[index]+rotation*offsets[i]
	body.collide_living(before,dt)
	body.max_speed=velocity.length()
	if body.frame_contacts>0 and body.max_speed<.25 and body.age>.45:body.quiet_time+=dt
	else:body.quiet_time=0
	if body.quiet_time>.45 or (body.age>6 and body.frame_contacts>0 and body.max_speed<.6):
		body.sleeping=true;body.sleep_reason="proxy_settled";body.max_speed=0;velocity=Vector3.ZERO
		body.corpse_stream.rest(body.positions[index],rotation)
	body.update_hitboxes()

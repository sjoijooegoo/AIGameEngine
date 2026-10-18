extends RefCounted
## Original Source samples, retimed to the bank's existing attack contact window.
static var catalogue: Dictionary={}
var actor: CharacterBody3D
var clips: Dictionary={}
var roles: Dictionary={}
var variation := 0
var phase := 0.0
var previous_position:=Vector3.ZERO
var last_source := ""
var gait_key := ""
var gait_frame := 0
var locomotion_key := ""
var foot_locks: Dictionary={}
var leg_ids: Dictionary={}
var flinch_bones: Dictionary={}

func setup(owner_actor: CharacterBody3D) -> void:
	actor=owner_actor
	if catalogue.is_empty():catalogue=JSON.parse_string(FileAccess.get_file_as_string("res://data/infected_native_motion.json"))
	var pin: Dictionary=catalogue.models[actor.definition.model]
	actor.animator.add_animation_library("native",load(pin.resource))
	clips=pin.clips
	for key in clips:
		var role: String=clips[key].role
		if not roles.has(role):roles[role]=[]
		roles[role].append(key)
	for role in roles:roles[role].sort()
	variation=posmod(str(actor.definition.id).hash(),997)
	for side in ["L","R"]:
		leg_ids[side]=[actor.skeleton.find_bone("ValveBiped.Bip01_"+side+"_Thigh"),actor.skeleton.find_bone("ValveBiped.Bip01_"+side+"_Calf"),actor.skeleton.find_bone("ValveBiped.Bip01_"+side+"_Foot")]
	for key in roles.flinch:
		var animation: Animation=actor.animator.get_animation("native/"+key)
		var indices:=PackedInt32Array()
		for track in animation.get_track_count():
			var bone: int=actor.skeleton.find_bone(animation.track_get_path(track).get_subname(0))
			indices.append(bone if bone>=0 and actor.skeleton.get_bone_parent(bone)>=0 else -1)
		flinch_bones[key]=indices
	reset()

func reset() -> void:
	phase=float(variation%100)/100.0;previous_position=actor.global_position
	foot_locks.clear();gait_key="";locomotion_key=""

func choice(role: String, serial: int=0) -> String:
	return roles[role][(variation+serial)%roles[role].size()]

func sample(dt: float) -> Dictionary:
	var key: String=choice("idle")
	var time: float=fmod(actor.clock+float(variation)*.137,float(clips[key].length))
	var displacement: Vector3=actor.global_position-previous_position
	var moved: float=Vector2(displacement.x,displacement.z).length()
	previous_position=actor.global_position
	gait_key=""
	if actor.mode in ["chase","return"] and (Vector2(actor.velocity.x,actor.velocity.z).length()>.15 or actor.locomotion_recovery>0 and not locomotion_key.is_empty()):
		var running: bool=actor.speed>2
		key=choice("run" if running else "walk")
		locomotion_key=key
		# Advance gait with distance, so blocked actors do not run in place.
		var gait: Dictionary=clips[key].gait
		phase+=minf(moved,.3)/(float(gait.stride_m)*actor.model.scale.y)
		time=fposmod(phase,1.0)*float(clips[key].length)
		gait_key=key;gait_frame=mini(int(time*float(clips[key].fps)),int(clips[key].frames)-1)
	elif actor.mode=="hurt" and not actor.strong_reaction and not locomotion_key.is_empty():
		# Follow backward displacement through the current stride, rather than
		# freezing a raised leg or resetting both legs through an idle pose.
		key=locomotion_key
		phase+=clampf(displacement.dot(-actor.global_basis.z),-.3,.3)/(float(clips[key].gait.stride_m)*actor.model.scale.y)
		time=fposmod(phase,1.0)*float(clips[key].length)
		gait_key=key;gait_frame=mini(int(time*float(clips[key].fps)),int(clips[key].frames)-1)
	elif actor.mode=="attack":
		key=choice("attack",actor.attack_serial)
		var length: float=clips[key].length
		var contact: float=length*float(clips[key].contact)
		var hit: float=actor.motion_profile.contact
		time=contact*clampf(actor.state_time/hit,0,1) if actor.state_time<=hit else lerpf(contact,length,clampf((actor.state_time-hit)/(float(actor.motion_profile.duration)-hit),0,1))
	elif actor.mode=="hurt" and actor.strong_reaction and actor.reaction_time<actor.reaction_duration:
		var index: int={"front":0,"back":1,"left":2,"right":3}[actor.reaction_direction]
		key=roles.shove[index]
		time=minf(actor.reaction_time*1.35,float(clips[key].length)-.001)
	last_source=clips[key].source
	return {"clip":"native/"+key,"time":minf(time,float(clips[key].length)-.0001)}

func ground_feet(dt: float) -> void:
	if gait_key.is_empty() or not actor.is_on_floor() or actor.global_position.distance_squared_to(actor.game.player.global_position)>64:
		foot_locks.clear();return
	var gait: Dictionary=clips[gait_key].gait
	var rig: Skeleton3D=actor.skeleton
	var poses: Dictionary={}
	# Cache both chains before mutation: two-bone analytic IK needs no repeated
	# whole-skeleton update between hip/knee rotations.
	for side in leg_ids:
		poses[side]=[]
		for bone in leg_ids[side]:poses[side].append(rig.global_transform*rig.get_bone_global_pose(bone))
	for side in leg_ids:
		var chain: Array=poses[side];var ankle: Vector3=chain[2].origin
		var stance: bool=gait.contacts[side][gait_frame]
		var lock: Dictionary=foot_locks.get(side,{"active":false,"weight":0.0,"point":ankle})
		if stance and not lock.active:
			var query:=PhysicsRayQueryParameters3D.create(ankle+Vector3.UP*.3,ankle-Vector3.UP*.42,1)
			var hit: Dictionary=actor.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.normal.y<.65:stance=false
			else:lock.point=Vector3(ankle.x,hit.position.y+float(gait.ankle_height_m[side])*actor.model.scale.y,ankle.z)
		lock.active=stance;lock.weight=move_toward(float(lock.weight),1.0 if stance else 0.0,dt*20)
		foot_locks[side]=lock
		if lock.weight<=.001:continue
		var target: Vector3=ankle+(Vector3(lock.point)-ankle).limit_length(.14)*float(lock.weight)
		var hip: Vector3=chain[0].origin;var knee: Vector3=chain[1].origin
		var upper: float=hip.distance_to(knee);var lower: float=knee.distance_to(ankle)
		var direction: Vector3=(target-hip).normalized()
		var distance: float=clampf(hip.distance_to(target),absf(upper-lower)+.005,(upper+lower)*.998)
		var pole: Vector3=knee-hip-direction*(knee-hip).dot(direction)
		if pole.length_squared()<.00001:pole=-actor.global_basis.z
		pole= pole.normalized()
		var along: float=(upper*upper-lower*lower+distance*distance)/(2*distance)
		var elbow: Vector3=hip+direction*along+pole*sqrt(maxf(0,upper*upper-along*along))
		var hip_turn:=Quaternion((knee-hip).normalized(),(elbow-hip).normalized())
		var moved_ankle: Vector3=hip+hip_turn*(ankle-hip)
		var knee_turn:=Quaternion((moved_ankle-elbow).normalized(),(hip+direction*distance-elbow).normalized())
		var indices: Array=leg_ids[side]
		var hip_basis: Quaternion=chain[0].basis.get_rotation_quaternion()
		var knee_basis: Quaternion=hip_turn*chain[1].basis.get_rotation_quaternion()
		var total: Quaternion=knee_turn*hip_turn
		var foot_basis: Quaternion=total*chain[2].basis.get_rotation_quaternion()
		for bone in indices:actor.remember_base_bone(bone)
		rig.set_bone_pose_rotation(indices[0],(rig.get_bone_pose_rotation(indices[0])*hip_basis.inverse()*hip_turn*hip_basis).normalized())
		rig.set_bone_pose_rotation(indices[1],(rig.get_bone_pose_rotation(indices[1])*knee_basis.inverse()*knee_turn*knee_basis).normalized())
		rig.set_bone_pose_rotation(indices[2],(rig.get_bone_pose_rotation(indices[2])*foot_basis.inverse()*total.inverse()*foot_basis).normalized())

func flinch() -> void:
	if actor.reaction_time>=actor.reaction_duration or actor.strong_reaction:return
	if actor.reactions.pistol_layer:return
	var key: String=choice("flinch",actor.reaction_serial)
	if actor.definition.model=="hunter":key=roles.flinch[1 if actor.reaction_zone=="head" else 2 if actor.reaction_zone=="leg" else 3 if actor.reaction_direction=="back" else 0]
	var animation: Animation=actor.animator.get_animation("native/"+key)
	var time: float=clampf(actor.reaction_time/actor.reaction_duration,0,1)*animation.length
	var weight: float=sin(PI*clampf(actor.reaction_time/actor.reaction_duration,0,1))*actor.reaction_strength
	for track in animation.get_track_count():
		var bone: int=flinch_bones[key][track]
		if bone<0:continue
		var delta: Quaternion=animation.rotation_track_interpolate(track,time)
		actor.remember_base_bone(bone)
		actor.skeleton.set_bone_pose_rotation(bone,(actor.skeleton.get_bone_pose_rotation(bone)*Quaternion.IDENTITY.slerp(delta,weight)).normalized())

func align_contact() -> void:
	# Keep original wind-up/follow-through; only correct reach close to contact.
	var distance: float=actor.global_position.distance_to(actor.game.player.global_position)
	if distance>float(actor.stats.reach)+.4:return
	var contact: float=actor.motion_profile.contact
	var weight: float=1.0-smoothstep(.035,.17,absf(actor.state_time-contact))
	if weight<=0:return
	var target: Vector3=actor.game.player.global_position+Vector3.UP*1.35
	var left: float=actor.bone_position("L_Hand").distance_squared_to(target)
	var right: float=actor.bone_position("R_Hand").distance_squared_to(target)
	actor.reach_arm("L" if left<right else "R",target+actor.global_basis.z*.14,weight)

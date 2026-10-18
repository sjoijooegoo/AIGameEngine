extends RefCounted
## Reactive offsets stay separate from locomotion and its crossfade.
const HEADS := [
	{"id":"back_snap","head":Vector3(26,0,2),"chest":Vector3(7,0,0),"arm":6.0,"peak":.085,"duration":.48,"step":1.0},
	{"id":"left_twist","head":Vector3(18,-24,-16),"chest":Vector3(6,-10,-6),"arm":14.0,"peak":.10,"duration":.52,"step":.90},
	{"id":"right_twist","head":Vector3(20,26,17),"chest":Vector3(7,11,7),"arm":-14.0,"peak":.095,"duration":.51,"step":1.05},
	{"id":"shoulder_recoil","head":Vector3(16,-6,-8),"chest":Vector3(12,8,-7),"arm":20.0,"peak":.13,"duration":.58,"step":1.10}
]
const BONES := ["Spine","Spine1","Spine2","Head1","L_UpperArm","R_UpperArm","L_Forearm","R_Forearm","L_Thigh","R_Thigh"]
var actor: CharacterBody3D
var profile: Dictionary={}
var serial := 0
var blend_id := ""
var pistol_layer := false
var part := ""
var incoming:=Vector3.ZERO
var offcenter:=0.0
var previous_deltas: Dictionary={}
var current_deltas: Dictionary={}
var peak_degrees := 0.0

func setup(owner_actor: CharacterBody3D) -> void:actor=owner_actor

func reset() -> void:
	profile={};serial=0;blend_id="";pistol_layer=false;part="";previous_deltas.clear();current_deltas.clear();peak_degrees=0

func begin(info: Dictionary) -> void:
	previous_deltas=current_deltas.duplicate();profile={};blend_id="";peak_degrees=0
	pistol_layer=info.get("weapon","")=="pistol"
	if info.get("weapon","") not in ["pistol","shotgun"]:current_deltas.clear();return
	part=info.get("part","Head" if info.get("head",false) else "Body")
	incoming=actor.reaction_vector
	var point: Vector3=info.get("point",actor.global_position)
	offcenter=clampf(actor.to_local(point).x/.30,-1,1)
	if info.get("head",false):
		serial+=1
		profile=HEADS[posmod(actor.native_motion.variation+serial-1,HEADS.size())].duplicate()
		blend_id=str(profile.id)+"_"+actor.reaction_direction
	else:
		profile={"id":part,"peak":.085,"duration":.28 if pistol_layer else actor.reaction_duration,"step":1.0}
		blend_id=part+"_"+actor.reaction_direction
	if not pistol_layer:profile.duration=maxf(float(profile.duration),actor.reaction_duration)
	actor.reaction_duration=float(profile.duration)

func apply() -> void:
	if profile.is_empty():return
	if actor.reaction_time>=actor.reaction_duration:current_deltas.clear();peak_degrees=0;return
	var base: Dictionary={}
	for bone in BONES:base[bone]=actor.skeleton.get_bone_pose_rotation(actor.bone_ids[bone])
	var t: float=actor.reaction_time
	var peak: float=profile.peak
	var amount: float=smoothstep(0,peak,t)*(1-smoothstep(peak,actor.reaction_duration,t))
	var follow: float=sin(PI*clampf((t-peak)/(actor.reaction_duration-peak),0,1))*.08
	var gain: float=actor.reaction_strength
	if part=="Head":
		if not pistol_layer:gain*=.55
		var head: Vector3=profile.head
		var chest: Vector3=profile.chest
		# Incoming direction drives the main recoil; authored variation adds
		# smaller twist/shoulder accents instead of replacing that direction.
		head=Vector3(head.x*incoming.z,head.y*.65+offcenter*8,head.z*.45-incoming.x*26)
		chest=Vector3(chest.x*incoming.z,chest.y*.55-offcenter*5,chest.z*.45-incoming.x*9)
		turn("Spine2",chest*(amount+follow)*gain)
		turn("Head1",head*(amount-follow)*gain)
		var arm: float=profile.arm
		turn("L_UpperArm",Vector3(-absf(arm)*incoming.z,0,-arm*.4)*amount*gain)
		turn("R_UpperArm",Vector3(-absf(arm)*incoming.z*.55,0,arm*.3)*amount*gain)
	elif part in ["ArmL","ArmR"]:
		var side: String="L" if part=="ArmL" else "R"
		turn(side+"_UpperArm",Vector3(18*incoming.z,-10*incoming.x,(-14 if side=="L" else 14))*amount*gain)
		turn(side+"_Forearm",Vector3(-18,0,0)*amount*gain)
		turn("Spine2",Vector3(2*incoming.z,0,-incoming.x)*amount*gain)
	elif part in ["LegL","LegR"]:
		turn("L_Thigh" if part=="LegL" else "R_Thigh",Vector3(12*incoming.z,0,-7*incoming.x)*amount*gain)
		turn("Spine",Vector3(-2*incoming.z,0,2*incoming.x)*amount*gain)
	else:
		var lower: bool=actor.reaction_zone=="abdomen"
		turn("Spine1" if lower else "Spine2",Vector3(9*incoming.z,-offcenter*4,-6*incoming.x)*amount*gain)
	var weight:=smoothstep(0,.10,t)
	peak_degrees=0
	for bone in BONES:
		var index: int=actor.bone_ids[bone]
		var delta: Quaternion=base[bone].inverse()*actor.skeleton.get_bone_pose_rotation(index)
		if bone=="Head1":
			var angle:=Quaternion.IDENTITY.angle_to(delta)
			if angle>deg_to_rad(32):delta=Quaternion.IDENTITY.slerp(delta,deg_to_rad(32)/angle)
		var previous: Quaternion=previous_deltas.get(bone,Quaternion.IDENTITY)
		var blended: Quaternion=previous.slerp(delta,weight).normalized()
		current_deltas[bone]=blended
		peak_degrees=maxf(peak_degrees,rad_to_deg(Quaternion.IDENTITY.angle_to(blended)))
		actor.remember_base_bone(index)
		actor.skeleton.set_bone_pose_rotation(index,(base[bone]*blended).normalized())

func turn(bone: String,degrees: Vector3) -> void:
	actor.rotate_world(bone,actor.global_basis.x,deg_to_rad(degrees.x))
	actor.rotate_world(bone,actor.global_basis.y,deg_to_rad(degrees.y))
	actor.rotate_world(bone,actor.global_basis.z,deg_to_rad(degrees.z))

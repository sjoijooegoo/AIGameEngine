extends Node3D
## An original full-body skeleton is always available, including on a clean clone.
## Optional local L4D2 reference is loaded only on clients; never on the server.
const COLORS := [Color("50b7d4"),Color("e9ad49"),Color("79b777"),Color("d078a9")]
var rig: Skeleton3D
var animator: AnimationPlayer
var clock := 0.0
var current_motion := "idle"
var source := "project_authored"
var bones: Dictionary={}
var parts: Array=[]

func setup(slot: int) -> void:
	var reference:="res://coop/local_reference/survivor.glb"
	var manifest:="res://coop/local_reference/manifest.json"
	if FileAccess.file_exists(manifest):
		var metadata=JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if metadata is Dictionary and str(metadata.get("resource","")).begins_with("res://coop/local_reference/"):
			reference=str(metadata.resource)
	if ResourceLoader.exists(reference):
		var model: Node3D=load(reference).instantiate();add_child(model)
		var rigs:=model.find_children("*","Skeleton3D",true,false)
		var players:=model.find_children("*","AnimationPlayer",true,false)
		if not rigs.is_empty() and not players.is_empty():
			rig=rigs[0];animator=players[0]
			animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for clip in animator.get_animation_list():animator.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
			source="local_l4d2_reference"
			return
		model.queue_free()
	rig=Skeleton3D.new();rig.name="SurvivorSkeleton";add_child(rig)
	bone("hips","",Vector3(0,.88,0))
	bone("spine","hips",Vector3(0,.20,0))
	bone("chest","spine",Vector3(0,.20,0))
	bone("neck","chest",Vector3(0,.17,0))
	bone("head","neck",Vector3(0,.12,0))
	for side in [-1,1]:
		var key:="left" if side==-1 else "right"
		bone(key+"_arm","chest",Vector3(side*.23,.08,0))
		bone(key+"_forearm",key+"_arm",Vector3(0,-.28,0))
		bone(key+"_hand",key+"_forearm",Vector3(0,-.25,0))
		bone(key+"_thigh","hips",Vector3(side*.13,-.02,0))
		bone(key+"_shin",key+"_thigh",Vector3(0,-.40,0))
		bone(key+"_foot",key+"_shin",Vector3(0,-.38,0))
	var shirt:=material(COLORS[slot%4]);var pants:=material(Color("27343f"));var skin:=material(Color("bd9172"));var boots:=material(Color("172028"))
	part("chest",Vector3(.43,.42,.25),Vector3(0,-.10,0),shirt)
	part("hips",Vector3(.31,.20,.23),Vector3(0,-.03,0),pants)
	part("neck",Vector3(.10,.12,.11),Vector3.ZERO,skin)
	part("head",Vector3(.18,.23,.19),Vector3(0,.035,-.01),skin)
	part("head",Vector3(.17,.06,.03),Vector3(0,.07,-.112),boots)
	for key in ["left","right"]:
		part(key+"_arm",Vector3(.13,.28,.15),Vector3(0,-.14,0),shirt)
		part(key+"_forearm",Vector3(.10,.25,.12),Vector3(0,-.125,0),skin)
		part(key+"_hand",Vector3(.095,.12,.10),Vector3(0,-.055,0),skin)
		part(key+"_thigh",Vector3(.14,.40,.18),Vector3(0,-.20,0),pants)
		part(key+"_shin",Vector3(.12,.38,.14),Vector3(0,-.19,0),pants)
		part(key+"_foot",Vector3(.14,.10,.27),Vector3(0,-.01,-.065),boots)
	animator=AnimationPlayer.new();add_child(animator)
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library:=AnimationLibrary.new()
	for clip in ["idle","walk","run"]:library.add_animation(clip,make_animation(clip))
	animator.add_animation_library("",library)

func material(color: Color) -> StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.albedo_color=color;value.roughness=.85;return value

func bone(label: String, parent: String, offset: Vector3) -> void:
	var index:=rig.get_bone_count();rig.add_bone(label);bones[label]=index
	if not parent.is_empty():rig.set_bone_parent(index,bones[parent])
	rig.set_bone_rest(index,Transform3D(Basis.IDENTITY,offset));rig.set_bone_pose_position(index,offset)

func part(label: String, size: Vector3, offset: Vector3, mat: Material) -> void:
	var attachment:=Node3D.new();rig.add_child(attachment)
	attachment.transform=rig.get_bone_global_rest(bones[label])
	parts.append({"node":attachment,"bone":bones[label]})
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size
	mesh.mesh=box;mesh.material_override=mat;mesh.position=offset;attachment.add_child(mesh)

func make_animation(clip: String) -> Animation:
	var animation:=Animation.new();animation.length=2.0 if clip=="idle" else .90 if clip=="walk" else .62
	animation.loop_mode=Animation.LOOP_LINEAR
	for label in bones:
		var track:=animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track,NodePath("SurvivorSkeleton:"+label))
		for frame in range(25):
			var phase:=float(frame)/24.0*TAU;var wave:=sin(phase);var angle:=0.0
			var side:=1.0 if label.begins_with("left") else -1.0
			if clip=="idle":
				if label=="chest":angle=.025*wave
			else:
				var stride:=.48 if clip=="walk" else .75
				if label.ends_with("thigh"):angle=wave*side*stride
				if label.ends_with("shin"):angle=maxf(0,-wave*side)*(.7 if clip=="walk" else 1.1)
				if label.ends_with("arm") and not label.ends_with("forearm"):angle=-wave*side*stride*.7
				if label.ends_with("forearm"):angle=-.15 if clip=="walk" else -.55
				if label=="chest":angle=-.05 if clip=="walk" else -.12
			animation.rotation_track_insert_key(track,float(frame)/24.0*animation.length,Quaternion(Vector3.RIGHT,angle))
	return animation

func advance(dt: float, motion: String, speed: float) -> void:
	clock+=dt
	if animator==null:return
	var clip:=motion
	if not animator.has_animation(clip):
		for candidate in animator.get_animation_list():
			if candidate.to_lower().ends_with(motion):clip=candidate;break
	if not animator.has_animation(clip):return
	if animator.current_animation!=clip:animator.play(clip,.12)
	var rate:=1.0 if motion=="idle" else clampf(speed/(2.8 if motion=="walk" else 4.6),.2,1.8)
	animator.advance(dt*rate);current_motion=motion
	if source=="project_authored":
		# This segmented rig has no Skin resource to trigger render-skeleton updates.
		# Sample its real animated bone transforms explicitly for the body pieces.
		rig.force_update_all_bone_transforms()
		for part in parts:part.node.transform=rig.get_bone_global_pose(part.bone)

func observe() -> Dictionary:
	var leg:=rig.find_bone("left_thigh") if source=="project_authored" else rig.find_bone("ValveBiped.Bip01_L_Thigh")
	var pose:=rig.get_bone_pose_rotation(leg) if leg>=0 else Quaternion.IDENTITY
	return {"source":source,"bones":rig.get_bone_count() if rig else 0,"motion":current_motion,"time":animator.current_animation_position if animator and not animator.current_animation.is_empty() else 0.0,"clips":animator.get_animation_list() if animator else [],"leg_rotation":[pose.x,pose.y,pose.z,pose.w]}

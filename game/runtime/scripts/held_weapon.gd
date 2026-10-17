extends SubViewportContainer
## Native skinned left arm; the flashlight follows an authored hand-bone socket.
var model: Node3D
var grip_position := Vector3(-.18,-.16,-.40)
var distance_to_wall := 10.0
var viewport_3d: SubViewport
var inspection_camera: Camera3D
var animator: AnimationPlayer
var skeleton: Skeleton3D
var socket: Node3D
var lens: Marker3D
var animation_name: StringName
var animation_time := 0.0
var rigged_hand: Node3D
var strike_time := -1.0

func setup(hand_resource: String, torch_resource: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	stretch=true
	viewport_3d=SubViewport.new()
	viewport_3d.transparent_bg=true
	viewport_3d.own_world_3d=true
	viewport_3d.gui_disable_input=true
	viewport_3d.size=Vector2i(1280,720)
	viewport_3d.msaa_3d=Viewport.MSAA_2X
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport_3d)
	inspection_camera=Camera3D.new()
	inspection_camera.current=true
	inspection_camera.near=.025
	inspection_camera.fov=75
	viewport_3d.add_child(inspection_camera)
	model=Node3D.new()
	viewport_3d.add_child(model)
	rigged_hand=(load(hand_resource) as PackedScene).instantiate() as Node3D
	model.add_child(rigged_hand)
	var origin:=rigged_hand.find_child("GripOrigin",true,false) as Node3D
	assert(origin,"Skinned hand must preserve its authored grip origin")
	# Cancel only outer asset normalization, preserving skeleton and Skin binds.
	rigged_hand.position-=origin.global_position
	skeleton=rigged_hand.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	animator=rigged_hand.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	socket=rigged_hand.find_child("FlashlightSocket",true,false) as Node3D
	assert(socket and socket.get_parent() is BoneAttachment3D,"Torch socket must follow a bone")
	for clip in animator.get_animation_list():
		if clip!="RESET":animation_name=clip;break
	assert(not animation_name.is_empty())
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.play(animation_name)
	animator.seek(0,true)
	animator.advance(0)
	var torch: Node3D=(load(torch_resource) as PackedScene).instantiate()
	socket.add_child(torch)
	lens=Marker3D.new()
	lens.name="TorchLens"
	# Native torch axis is +Z, with Y=[0,.0564583] and Z=±.117723.
	lens.position=Vector3(0,.02822915,.11772305)
	lens.rotation.y=PI
	torch.add_child(lens)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("9aa591")
	env.environment.ambient_light_energy=.35
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	viewport_3d.add_child(env)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-35,-25,0)
	light.light_color=Color("cdd2be")
	light.light_energy=.40
	viewport_3d.add_child(light)
	advance(0,false,10.0)

func advance(tick: int, moving: bool, wall_distance: float) -> void:
	distance_to_wall=wall_distance
	animation_time=fmod(float(tick)/60.0*(1.7 if moving else .65),animator.get_animation(animation_name).length)
	animator.seek(animation_time,true)
	animator.advance(0)
	skeleton.force_update_all_bone_transforms()
	var retract:=clampf((.85-wall_distance)/.6,0,1)
	var bob:=sin(float(tick)*.13)*.005 if moving else 0.0
	model.position=grip_position+Vector3(0,abs(bob)-retract*.22,retract*.23)
	model.rotation.z=deg_to_rad(-55)+bob*.3
	if strike_time>=0:
		var thrust:=sin(clampf(strike_time/.42,0,1)*PI)
		model.position+=Vector3(.06,.035,-.10)*thrust
	# Manual animation sampling must update the attachment before the world
	# spotlight copies the lens transform, not one rendered frame afterwards.
	(socket.get_parent() as BoneAttachment3D).on_skeleton_update()

func light_transform() -> Transform3D:
	return Transform3D(lens.global_basis.orthonormalized(),lens.global_position)

func inspect_grip(name: String) -> void:
	inspection_camera.fov=40 if name!="player" else 75
	if name=="player":
		inspection_camera.position=Vector3.ZERO
		inspection_camera.rotation=Vector3.ZERO
	else:
		var eyes: Dictionary={"grip_side":Vector3(.30,.02,.06),"grip_palm":Vector3(-.28,.02,.06),"grip_top":Vector3(.03,.30,.06),"grip_back":Vector3(.06,.02,.36)}
		inspection_camera.position=model.transform*eyes.get(name,eyes.grip_side)
		inspection_camera.look_at(model.transform*Vector3(0,-.015,-.02),Vector3.UP)

func grip_state() -> Dictionary:
	var attached:=socket.get_parent() as BoneAttachment3D
	return {"skinned":true,"bones":skeleton.get_bone_count(),"hand_bone":attached.bone_name,"animation":str(animation_name),"animation_time":animation_time,"wall_distance":distance_to_wall,"socket_position":[socket.global_position.x,socket.global_position.y,socket.global_position.z],"lens_position":[lens.global_position.x,lens.global_position.y,lens.global_position.z]}

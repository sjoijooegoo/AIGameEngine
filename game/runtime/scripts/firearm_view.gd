extends SubViewportContainer
## Both native skins are sampled together. Rendering never advances animation.
var viewport_3d: SubViewport
var camera: Camera3D
var models: Dictionary={}
var animators: Dictionary={}
var muzzles: Dictionary={}
var selected := "pistol"
var clock := 0.0
var clip_name := "idle"
var clip_time := 0.0
var flash: MeshInstance3D
var flash_light: OmniLight3D
var casings: Array=[]
var casing_meshes: Dictionary={}
var rigs: Dictionary={}
var attachments: Dictionary={}
var blends: Dictionary={}
var initialized: Dictionary={}
var last_weapon := ""
var last_elapsed := -1.0
var last_clip := ""
var sway := Vector2.ZERO
var feedback_rotation := Vector3.ZERO
var feedback_offset := Vector3.ZERO
var transition_count := 0
var sleeves: Dictionary={}
var baton_grip: Dictionary={}
var wall_retract := 0.0

func setup(pins: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE;stretch=true
	viewport_3d=SubViewport.new();viewport_3d.transparent_bg=true;viewport_3d.own_world_3d=true
	viewport_3d.msaa_3d=Viewport.MSAA_2X
	viewport_3d.gui_disable_input=true;viewport_3d.size=Vector2i(1280,720);viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport_3d)
	camera=Camera3D.new();camera.current=true;camera.near=.015;camera.fov=50
	viewport_3d.add_child(camera)
	for key in pins:
		var model: Node3D=(load(pins[key].resource) as PackedScene).instantiate()
		viewport_3d.add_child(model)
		var origin:=model.find_child("ViewmodelOrigin",true,false) as Node3D
		assert(origin,"Viewmodel has no source origin")
		model.position-=origin.global_position
		model.set_meta("origin_position",model.position)
		models[key]=model
		var animator: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
		animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in pins[key].clips:assert(animator.has_animation(clip),"Missing native clip: "+clip)
		animators[key]=animator;muzzles[key]=model.find_child("Muzzle",true,false)
		rigs[key]=model.find_children("*","Skeleton3D",true,false)
		attachments[key]=model.find_children("*","BoneAttachment3D",true,false)
		blends[key]=preload("res://scripts/pose_transition.gd").new();blends[key].setup(rigs[key])
		sleeves[key]=preload("res://scripts/viewmodel_sleeves.gd").new();sleeves[key].setup(model)
		if key=="baton":
			animator.play("idle");animator.seek(0,true);animator.advance(0)
			for rig in rigs[key]:rig.force_update_all_bone_transforms()
			var hand_rig: Skeleton3D=sleeves[key].skeleton
			var weapon_rig: Skeleton3D
			for rig in rigs[key]:
				if rig!=hand_rig:weapon_rig=rig
			var hand_id:=hand_rig.find_bone("ValveBiped.Bip01_R_Hand")
			var weapon_id:=weapon_rig.find_bone("ValveBiped.weapon_bone")
			assert(hand_id>=0 and weapon_id>=0)
			var hand: Transform3D=hand_rig.global_transform*hand_rig.get_bone_global_pose(hand_id)
			var handle: Transform3D=weapon_rig.global_transform*weapon_rig.get_bone_global_pose(weapon_id)
			baton_grip={"hand_rig":hand_rig,"weapon_rig":weapon_rig,"hand_id":hand_id,"weapon_id":weapon_id,"relative":hand.affine_inverse()*handle}
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("a5aea3");env.environment.ambient_light_energy=.65
	viewport_3d.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-40,0);light.light_energy=.8;viewport_3d.add_child(light)
	flash=MeshInstance3D.new()
	var shape:=QuadMesh.new();shape.size=Vector2(.14,.14);flash.mesh=shape
	var mat:=ShaderMaterial.new();mat.shader=preload("res://shaders/muzzle_flash.gdshader");flash.material_override=mat
	viewport_3d.add_child(flash);flash.visible=false
	flash_light=OmniLight3D.new();flash_light.light_color=Color(1,.7,.35);flash_light.omni_range=1.4;viewport_3d.add_child(flash_light);flash_light.visible=false
	# Primitive surface/material creation can synchronously prepare render
	# pipelines. Build once during loading, never on the pump/ejection frame.
	for weapon in ["pistol","shotgun"]:
		var mesh:=CylinderMesh.new();mesh.top_radius=.005;mesh.bottom_radius=.005;mesh.height=.025 if weapon=="pistol" else .055
		var material:=StandardMaterial3D.new();material.albedo_color=Color("ac8b40") if weapon=="pistol" else Color("84251a");material.metallic=.7;material.roughness=.4
		mesh.material=material
		casing_meshes[weapon]=mesh
		# Assign to an instance now so surface preparation happens at startup.
		var warmup:=MeshInstance3D.new();warmup.mesh=mesh;warmup.visible=false;viewport_3d.add_child(warmup)

func sample(weapon: String, clip: String, elapsed: float, duration: float, moving: bool, wall: float, flash_time: float, dt: float) -> void:
	var weapon_changed:=last_weapon!=weapon
	selected=weapon;last_weapon=weapon;clock+=dt;visible=weapon!="torch"
	sway=sway.lerp(Vector2.ZERO,1-exp(-dt*12))
	for key in models:models[key].visible=key==weapon
	# Casings use the fixed clock even while the torch is selected.
	for casing in casings.duplicate():
		casing.age+=dt;casing.velocity.y-=3*dt;casing.node.position+=casing.velocity*dt;casing.node.rotate_z(dt*10)
		if casing.age>1.0:casing.node.queue_free();casings.erase(casing)
	if not visible:return
	camera.fov=50
	var a: AnimationPlayer=animators[weapon]
	if not weapon_changed and initialized.get(weapon,false) and (clip!=last_clip or elapsed<last_elapsed-.00001):
		blends[weapon].begin(.035 if clip in ["fire","fire_last"] else .10);transition_count+=1
	elif weapon_changed:blends[weapon].reset()
	initialized[weapon]=true;last_clip=clip;last_elapsed=elapsed
	clip_name=clip
	var length:=a.get_animation(clip).length
	clip_time=fmod(elapsed,length) if clip=="idle" else minf(length,maxf(0,elapsed)/maxf(duration,.001)*length)
	if a.current_animation!=clip:a.play(clip)
	for rig in rigs[weapon]:rig.reset_bone_poses()
	a.seek(clip_time,true);a.advance(0)
	blends[weapon].apply(dt)
	for s in rigs[weapon]:
		s.force_update_all_bone_transforms()
	if weapon=="baton":
		# Source's additive weapon and arm tracks are independent. Preserve
		# the calibrated neutral palm-to-handle transform after pose blending,
		# so no interpolation or imported delta can make the club leave the hand.
		var hand: Transform3D=baton_grip.hand_rig.global_transform*baton_grip.hand_rig.get_bone_global_pose(baton_grip.hand_id)
		var target: Transform3D=baton_grip.weapon_rig.global_transform.affine_inverse()*hand*baton_grip.relative
		baton_grip.weapon_rig.set_bone_global_pose(baton_grip.weapon_id,target)
		baton_grip.weapon_rig.force_update_all_bone_transforms()
	for attachment in attachments[weapon]:attachment.on_skeleton_update()
	var retract_target:=clampf((.78-wall)/.52,0,1)
	var retract_rate:=10.0 if retract_target>wall_retract else 4.5
	wall_retract=move_toward(wall_retract,retract_target,retract_rate*dt)
	var sway_scale:=1.0-.70*wall_retract
	models[weapon].rotation=Vector3((.08 if weapon!="baton" else -.14)-.12*wall_retract+sway.y*sway_scale,sway.x*sway_scale,0)+feedback_rotation*.35
	var framing:=Vector3(0,-.055,.025) if weapon!="baton" else Vector3(.035,-.035,-.12)
	models[weapon].position=models[weapon].basis*Vector3(models[weapon].get_meta("origin_position"))+Vector3(sin(clock*9)*.005*sway_scale if moving else 0,abs(sin(clock*9))*.007*sway_scale if moving else 0,0)+Vector3(0,-.1*wall_retract,.13*wall_retract)+feedback_offset+framing
	sleeves[weapon].update()
	flash.visible=flash_time>0;flash_light.visible=flash.visible
	if flash.visible:
		flash.position=muzzles[weapon].global_position;flash.rotation=Vector3(0,0,clock*90);flash.scale=Vector3.ONE*(1.4 if weapon=="shotgun" else 1)
		flash_light.position=flash.position;flash_light.light_energy=.45

func eject(weapon: String) -> void:
	if weapon=="torch":return
	var node:=MeshInstance3D.new();node.mesh=casing_meshes[weapon]
	viewport_3d.add_child(node)
	# Source marker: X-forward, Y-left, Z-up. Follow the animated port.
	node.position=muzzles[weapon].global_transform*Vector3(-.12 if weapon=="pistol" else -.43,-.025,-.015)
	casings.append({"node":node,"age":0.0,"velocity":muzzles[weapon].global_basis*Vector3(-.15,-.8,.65)})

func mouse_motion(delta: Vector2) -> void:
	sway+=Vector2(-delta.x,delta.y)*.00015
	sway=sway.clamp(Vector2(-.035,-.025),Vector2(.035,.025))

func reset() -> void:
	clock=0;flash.visible=false;flash_light.visible=false;sway=Vector2.ZERO;wall_retract=0;initialized.clear();last_weapon="";last_elapsed=-1;last_clip="";transition_count=0
	for blend in blends.values():blend.reset()
	for c in casings:c.node.queue_free()
	casings.clear()

func observe() -> Dictionary:
	var skins: Array=[]
	if selected!="torch":
		for s in models[selected].find_children("*","Skeleton3D",true,false):skins.append(s.get_bone_count())
	return {"clip":clip_name,"time":clip_time,"skins":skins,"casings":casings.size(),"flash_visible":flash.visible,"transition_count":transition_count,"blending":blends[selected].active if selected!="torch" else false,"sway":[sway.x,sway.y],"wall_retract":wall_retract,"grip_error_m":grip_error()}

func grip_error() -> float:
	if selected!="baton":return 0
	var hand: Transform3D=baton_grip.hand_rig.global_transform*baton_grip.hand_rig.get_bone_global_pose(baton_grip.hand_id)
	var handle: Transform3D=baton_grip.weapon_rig.global_transform*baton_grip.weapon_rig.get_bone_global_pose(baton_grip.weapon_id)
	return (hand*baton_grip.relative).origin.distance_to(handle.origin)

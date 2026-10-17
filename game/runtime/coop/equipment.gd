extends Node3D
## Client-only world weapons. Named bone merging follows hands, clips and bolts.
var gun: Node3D
var muzzle: MeshInstance3D
var label: Label3D
var timer := 0.0
var last_shots := -1
var weapon := "pistol"
var dead := false
var sound: AudioStreamPlayer3D
var owner_body: CharacterBody3D
var models: Dictionary={}
var source := "project_authored"

func setup(player: CharacterBody3D) -> void:
	owner_body=player
	gun=Node3D.new();gun.name="WorldEquipment";add_child(gun)
	var path:="res://coop/local_reference/weapons.json"
	if FileAccess.file_exists(path) and player.avatar.source=="local_l4d2_reference":
		var manifest=JSON.parse_string(FileAccess.get_file_as_string(path))
		if manifest is Dictionary:
			for key in ["pistol","shotgun"]:
				var entry: Dictionary=manifest.get("weapons",{}).get(key,{})
				var resource:=str(entry.get("resource",""))
				if not resource.begins_with("res://coop/local_reference/") or not ResourceLoader.exists(resource):continue
				var model: Node3D=load(resource).instantiate();gun.add_child(model)
				var rigs:=model.find_children("*","Skeleton3D",true,false)
				if rigs.is_empty():model.queue_free();continue
				var rig: Skeleton3D=rigs[0];var mapping: Dictionary={}
				for i in rig.get_bone_count():
					var from: int=player.avatar.rig.find_bone(rig.get_bone_name(i))
					if from>=0:mapping[i]=from
				models[key]={"node":model,"rig":rig,"mapping":mapping,"muzzle":entry.muzzle_in_bone}
				model.hide()
	if not models.is_empty():source="local_l4d2_world_models"
	else:
		gun.position=Vector3(.21,1.27,-.32)
		part(Vector3(.065,.09,.30),Vector3.ZERO,Color("252b30"))
		part(Vector3(.05,.14,.075),Vector3(0,-.08,.08),Color("41413b"))
	muzzle=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.035;sphere.height=.07;muzzle.mesh=sphere
	var glow:=StandardMaterial3D.new();glow.albedo_color=Color("ffe3a0");glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;muzzle.material_override=glow;add_child(muzzle);muzzle.hide()
	label=Label3D.new();label.position.y=2.05;label.font_size=28;label.pixel_size=.003;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=preload("res://coop/avatar.gd").COLORS[player.slot%4];add_child(label)
	label.text=player.display_name
	sound=AudioStreamPlayer3D.new();sound.bus="WeaponSFX";sound.max_distance=35;sound.unit_size=3;add_child(sound)

func shot_audio(audio_bank: Node) -> void:
	if not audio_bank.streams.has(weapon):return
	sound.stream=audio_bank.streams[weapon][0]
	sound.volume_db=float(audio_bank.bank.events[weapon].gain_db)+preload("res://scripts/audio_mix.gd").trim("firearms",weapon,sound.stream.resource_path)
	if DisplayServer.get_name()!="headless":sound.play()

func part(size: Vector3, at: Vector3, tint: Color) -> void:
	var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;visual.mesh=mesh;visual.position=at
	var material:=StandardMaterial3D.new();material.albedo_color=tint;material.roughness=.55;visual.material_override=material;gun.add_child(visual)

func update_state(state: Dictionary,player: CharacterBody3D) -> void:
	dead=state.get("dead",false);weapon=state.get("weapon","pistol")
	var shots: int=state.get("shots",0)
	if last_shots>=0 and shots>last_shots:timer=.09
	last_shots=shots;player.avatar.combat_state(state)
	label.text=player.display_name+(" · 阵亡" if dead else " · %d" % int(state.get("hp",100)))
	gun.visible=not dead and weapon in ["pistol","shotgun"]
	for key in models:models[key].node.visible=key==weapon
	if models.is_empty():gun.scale.z=1.8 if weapon=="shotgun" else 1.0

func advance(dt: float,pitch: float) -> void:
	timer=maxf(0,timer-dt);muzzle.visible=timer>0 and gun.visible
	if models.has(weapon):
		var target: Skeleton3D=models[weapon].rig;var original: Skeleton3D=owner_body.avatar.rig
		var conversion: Transform3D=target.global_transform.affine_inverse()*original.global_transform
		for index in models[weapon].mapping:
			target.set_bone_global_pose(index,conversion*original.get_bone_global_pose(models[weapon].mapping[index]))
		target.force_update_all_bone_transforms()
		var bone:=original.find_bone("ValveBiped.weapon_bone")
		var at: Array=models[weapon].muzzle
		muzzle.global_position=original.global_transform*original.get_bone_global_pose(bone)*Vector3(at[0],at[1],at[2])
		sound.global_position=muzzle.global_position
	else:
		gun.rotation.x=pitch+timer*.7;muzzle.global_position=gun.to_global(Vector3(0,0,-.19))

func observe() -> Dictionary:
	var merged:=0
	var error:=0.0
	if models.has(weapon):
		merged=models[weapon].mapping.size()
		var target: Skeleton3D=models[weapon].rig;var original: Skeleton3D=owner_body.avatar.rig
		for index in models[weapon].mapping:
			var a: Vector3=(target.global_transform*target.get_bone_global_pose(index)).origin
			var b: Vector3=(original.global_transform*original.get_bone_global_pose(models[weapon].mapping[index])).origin
			error=maxf(error,a.distance_to(b))
	return {"source":source,"weapon":weapon,"visible":gun.visible,"merged_bones":merged,"bone_error":error,"muzzle":[muzzle.global_position.x,muzzle.global_position.y,muzzle.global_position.z]}

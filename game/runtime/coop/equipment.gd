extends Node3D
## Lightweight third-person equipment and teammate identity; no collision/damage.
var gun: Node3D
var muzzle: MeshInstance3D
var label: Label3D
var timer := 0.0
var last_shots := -1
var weapon := "pistol"
var dead := false
var color: Color
var sound: AudioStreamPlayer3D

func setup(player: CharacterBody3D) -> void:
	color=preload("res://coop/avatar.gd").COLORS[player.slot%4]
	gun=Node3D.new();gun.position=Vector3(.21,1.27,-.32);add_child(gun)
	part(Vector3(.065,.09,.30),Vector3.ZERO,Color("252b30"))
	part(Vector3(.05,.14,.075),Vector3(0,-.08,.08),Color("41413b"))
	muzzle=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.07;sphere.height=.14;muzzle.mesh=sphere;muzzle.position.z=-.19
	var glow:=StandardMaterial3D.new();glow.albedo_color=Color("ffe3a0");glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;muzzle.material_override=glow;gun.add_child(muzzle);muzzle.hide()
	label=Label3D.new();label.position.y=2.05;label.font_size=28;label.pixel_size=.003;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=color;add_child(label)
	label.text=player.display_name
	sound=AudioStreamPlayer3D.new();sound.bus="WeaponSFX";sound.max_distance=35;sound.unit_size=3;gun.add_child(sound)

func shot_audio(audio_bank: Node) -> void:
	if not audio_bank.streams.has(weapon):return
	sound.stream=audio_bank.streams[weapon][0]
	sound.volume_db=float(audio_bank.bank.events[weapon].gain_db)+preload("res://scripts/audio_mix.gd").trim("firearms",weapon,sound.stream.resource_path)
	if DisplayServer.get_name()!="headless":sound.play()

func part(size: Vector3, at: Vector3, tint: Color) -> void:
	var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;visual.mesh=mesh;visual.position=at
	var material:=StandardMaterial3D.new();material.albedo_color=tint;material.roughness=.55;visual.material_override=material;gun.add_child(visual)

func update_state(state: Dictionary, player: CharacterBody3D) -> void:
	dead=state.get("dead",false);weapon=state.get("weapon","pistol")
	var shots: int=state.get("shots",0)
	if last_shots>=0 and shots>last_shots:timer=.09
	last_shots=shots
	label.text=player.display_name+ (" · 阵亡" if dead else " · %d" % int(state.get("hp",100)))
	gun.visible=not dead and weapon in ["pistol","shotgun"]
	gun.scale.z=1.8 if weapon=="shotgun" else 1.0

func advance(dt: float, pitch: float) -> void:
	timer=maxf(0,timer-dt);muzzle.visible=timer>0
	gun.rotation.x=pitch+timer*.7

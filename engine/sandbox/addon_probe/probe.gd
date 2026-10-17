extends Node3D
## Isolated compatibility fixture; it does not replace the lab or bank controller.
const Props = preload("res://addons/ai_engine/fixtures/props.gd")
var player: CharacterBody3D
var camera: Camera3D
var host: PhantomCameraHost
var follow: PhantomCamera3D
var aim: PhantomCamera3D
var ticks := 0
var aiming := false
var overlay := true
var testing := false
var label: Label

func _ready() -> void:
	for pair in [["forward", KEY_W], ["back", KEY_S], ["left", KEY_A], ["right", KEY_D]]:
		InputMap.add_action(pair[0])
		var event := InputEventKey.new()
		event.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], event)
	Input.use_accumulated_input = false
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("1b293a")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var wall := Props.material(Color("4f6878"))
	Props.box(self, "Floor", Vector3(14, 0.2, 24), Vector3(0, -0.1, -7), Props.material(Color("303e49")), true)
	Props.box(self, "RearWall", Vector3(14, 4, 0.25), Vector3(0, 2, 3.5), wall, true)
	Props.box(self, "SideWall", Vector3(0.25, 4, 24), Vector3(3, 2, -7), wall, true)
	var ramp := Props.box(self, "StairApproachRamp", Vector3(3.4, 0.2, 8), Vector3(0, 1.17, -7), Props.material(Color("8d8064")), true)
	ramp.rotation_degrees.x = 18
	Props.box(self, "Landing", Vector3(3.4, 0.2, 5), Vector3(0, 2.45, -13), wall, true)
	for i in range(8):
		Props.box(self, "SideStep%d" % i, Vector3(1.4, 0.3 * (i + 1), 0.8), Vector3(-2.8, 0.15 * (i + 1), -3.8 - i * 0.8), wall, true)
	player = CharacterBody3D.new()
	player.collision_layer = 2
	player.collision_mask = 1
	player.position = Vector3(0, 0.1, -1)
	add_child(player)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	collider.shape = capsule
	collider.position.y = 0.8
	player.add_child(collider)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.6
	Props.mesh(player, "Player", mesh, Vector3(0, 0.8, 0), Props.material(Color("edb55f")))
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.1
	add_child(camera)
	host = PhantomCameraHost.new()
	host.interpolation_mode = PhantomCameraHost.InterpolationMode.MANUAL
	camera.add_child(host)
	follow = make_camera(10, 4.5, Vector3(0, 1.5, 0))
	aim = make_camera(0, 2.2, Vector3(0.55, 1.5, 0))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(label)
	DebugDrawManager.debug_enabled = OS.is_debug_build() and DisplayServer.get_name() != "headless"
	overlay = DebugDrawManager.debug_enabled
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ai-session="):
				testing = true
				var bridge := preload("res://addons/ai_engine/testing/bridge.gd").new()
				bridge.session = arg.trim_prefix("--ai-session=")
				bridge.adapter = preload("res://adapter.gd").new(self)
				add_child(bridge)
				break
	host.process(0.0)
	print("ADDON_PROBE_READY ", JSON.stringify({"debug_build": OS.is_debug_build(), "overlay": overlay, "dd3d_version": DebugDrawManager.get_addon_version_str(), "manual_host": host.interpolation_mode == 3}))

func make_camera(priority: int, distance: float, offset: Vector3) -> PhantomCamera3D:
	var pcam := PhantomCamera3D.new()
	pcam.priority = priority
	pcam.follow_mode = PhantomCamera3D.FollowMode.THIRD_PERSON
	pcam.follow_target = player
	pcam.follow_offset = offset
	pcam.spring_length = distance
	pcam.collision_mask = 1
	pcam.follow_damping = true
	pcam.follow_damping_value = Vector3(0.15, 0.15, 0.15)
	pcam.tween_resource = PhantomCameraTween.new()
	pcam.tween_resource.duration = 0.4
	pcam.rotation_degrees = Vector3(-12, 0, 0)
	add_child(pcam)
	# Host MANUAL does not stop inactive PhantomCamera nodes from ticking.
	# Disable their automatic callbacks; advance them alongside the active host.
	pcam.set_process(false)
	pcam.set_physics_process(false)
	return pcam

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			aiming = not aiming
			aim.priority = 20 if aiming else 0
		if event.physical_keycode == KEY_G and OS.is_debug_build():
			overlay = not overlay
			DebugDrawManager.debug_enabled = overlay and DisplayServer.get_name() != "headless"
	if event is InputEventMouseMotion:
		var angles := follow.get_third_person_rotation_degrees()
		angles.y -= event.relative.x * 0.12
		angles.x = clampf(angles.x - event.relative.y * 0.12, -55, 20)
		follow.set_third_person_rotation_degrees(angles)
		aim.set_third_person_rotation_degrees(angles)

func _physics_process(dt: float) -> void:
	if not testing:
		tick(dt)

func tick(dt: float) -> void:
	ticks += 1
	var direction := Input.get_vector("left", "right", "forward", "back")
	player.velocity.x = direction.x * 3.0
	player.velocity.z = direction.y * 3.0
	player.velocity.y -= 18.0 * dt
	player.move_and_slide()
	for pcam in [follow, aim]:
		if not pcam.is_active():
			pcam.process_logic(dt)
	host.process(dt)

func _process(_dt: float) -> void:
	# Render-only redraw keeps overlay visible while simulation is frozen.
	# Timed debug primitives are deliberately not used as a simulation clock.
	label.text = "PHANTOM CAMERA  +  DEBUG DRAW 3D\nWASD move  |  mouse orbit  |  F aim  |  G overlay\nTick %d  |  %s  |  overlay %s" % [ticks, "AIM" if aiming else "FOLLOW", overlay]
	if overlay and OS.is_debug_build():
		var style = DebugDraw3D.new_scoped_config().set_thickness(0.025)
		DebugDraw3D.draw_line(player.position + Vector3.UP, player.position + Vector3(0, 1, -4), Color("3bff9b"))
		DebugDraw3D.draw_sphere(player.position + Vector3.UP, 1.25, Color("ff638c"))
		DebugDraw3D.draw_box(Vector3(0, 1.0, -3), Quaternion.IDENTITY, Vector3(2, 2, 0.3), Color("36cfff"), true)
		style = null

func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func observe() -> Dictionary:
	return {"tick": ticks, "position": vec(player.position), "velocity": vec(player.velocity), "camera": vec(camera.global_position), "camera_rotation": vec(camera.global_rotation), "follow": vec(follow.global_position), "aim": vec(aim.global_position), "aiming": aiming, "overlay": overlay, "debug_enabled": DebugDrawManager.debug_enabled, "manual_mode": host.interpolation_mode, "debug_build": OS.is_debug_build()}

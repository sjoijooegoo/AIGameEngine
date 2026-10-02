extends Node3D

const Props = preload("res://scripts/props.gd")
const PlayerScript = preload("res://scripts/player.gd")
const NPCScript = preload("res://scripts/npc.gd")
const HudScript = preload("res://scripts/hud.gd")
const BridgeScript = preload("res://testing/bridge.gd")

var player: CharacterBody3D
var npc: CharacterBody3D
var hud: CanvasLayer
var pivot: Node3D
var camera: Camera3D
var inspection_camera: Camera3D
var door: StaticBody3D
var card: Node3D
var gallery: Node3D
var keys: Array = []
var door_open := false
var complete := false
var paused := false
var ticks := 0
var hint := ""
var events: Array = []
var testing := false
var inspection_view := "player"
var queued: Array[String] = []
var save_path := "user://lab_save.json"
var rng := RandomNumberGenerator.new()
var inspected_asset := "res://assets/inspection_crate.glb"

func _ready() -> void:
	_setup_input()
	_build_room()
	player = PlayerScript.new()
	add_child(player)
	npc = NPCScript.new()
	add_child(npc)
	pivot = Node3D.new()
	add_child(pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 3.2
	arm.collision_mask = 1
	arm.add_excluded_object(player.get_rid())
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 65
	arm.add_child(camera)
	camera.current = true
	inspection_camera = Camera3D.new()
	inspection_camera.fov = 55
	add_child(inspection_camera)
	hud = HudScript.new()
	add_child(hud)
	hud.resume_requested.connect(func(): set_paused(false))
	hud.restart_requested.connect(func(): reset_fixture("default"))
	hud.save_requested.connect(save_game)
	hud.load_requested.connect(load_game)
	reset_fixture("default")
	# The automation bridge is inert in release builds and absent without an explicit session.
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ai-session="):
				testing = true
				var session := arg.trim_prefix("--ai-session=")
				save_path = session.path_join("save.json")
				var bridge := BridgeScript.new()
				bridge.session = session
				bridge.adapter = preload("res://testing/lab_adapter.gd").new(self)
				add_child(bridge)
				break

func _setup_input() -> void:
	var mapping := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "run": KEY_SHIFT, "interact": KEY_E, "inventory": KEY_TAB, "pause": KEY_ESCAPE}
	for action in mapping:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = mapping[action]
		InputMap.action_add_event(action, event)
	Input.use_accumulated_input = false

func _build_room() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("253c51")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c3d8ed")
	env.ambient_light_energy = 0.35
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var light := OmniLight3D.new()
	light.position = Vector3(-4, 3, 2)
	light.omni_range = 12
	light.light_color = Color("a5cfe8")
	light.light_energy = 0.7
	add_child(light)
	var floor_mat := Props.material(Color.WHITE, 0.85)
	floor_mat.albedo_texture = load("res://assets/checker.png")
	floor_mat.uv1_scale = Vector3(12, 12, 1)
	Props.box(self, "Floor", Vector3(16, 0.25, 20), Vector3(0, -0.125, -1), floor_mat, true)
	var wall := Props.material(Color("69808b"))
	Props.box(self, "BackWall", Vector3(16, 3.6, 0.3), Vector3(0, 1.8, -10), wall, true)
	Props.box(self, "LeftWall", Vector3(0.3, 3.6, 20), Vector3(-8, 1.8, -1), wall, true)
	Props.box(self, "RightWall", Vector3(0.3, 3.6, 20), Vector3(8, 1.8, -1), wall, true)
	Props.box(self, "FrontWall", Vector3(16, 3.6, 0.3), Vector3(0, 1.8, 9), wall, true)
	Props.box(self, "PartitionLeft", Vector3(7, 2.8, 0.25), Vector3(-4.5, 1.4, -3), wall, true)
	Props.box(self, "PartitionRight", Vector3(7, 2.8, 0.25), Vector3(4.5, 1.4, -3), wall, true)
	door = Props.box(self, "SecurityDoor", Vector3(2, 2.8, 0.22), Vector3(0, 1.4, -3), Props.material(Color("c39554"), 0.35, 0.65), true)
	card = Props.box(self, "AccessCard", Vector3(0.35, 0.08, 0.22), Vector3(0, 0.75, 1.8), Props.material(Color("4aaedf"), 0.25))
	Props.box(self, "CardStand", Vector3(0.55, 0.65, 0.55), Vector3(0, 0.325, 1.8), Props.material(Color("243d50")))
	gallery = Node3D.new()
	gallery.name = "AssetGallery"
	add_child(gallery)
	for i in range(3):
		var sphere := SphereMesh.new()
		sphere.radius = 0.55
		sphere.height = 1.1
		var mat := Props.material(Color("c2a976") if i == 2 else Color("90bed1"), [0.08, 0.5, 0.95][i], 0.85 if i == 2 else 0.0)
		Props.mesh(gallery, "Material_%d" % i, sphere, Vector3(-6.2 + i * 1.65, 1.25, -0.8), mat)
		Props.box(gallery, "Pedestal_%d" % i, Vector3(1.3, 0.65, 1.3), Vector3(-6.2 + i * 1.65, 0.325, -0.8), Props.material(Color("263d4c")))
	var imported: PackedScene = load("res://assets/inspection_crate.glb")
	var crate: Node3D = imported.instantiate()
	crate.name = "ImportedCrate"
	crate.position = Vector3(-5, 0.65, 2.1)
	gallery.add_child(crate)
	_add_sign("材质 / 纹理 / 模型", Vector3(-4.5, 2.45, -1.6))
	_add_sign("安全门 · 门卡通行", Vector3(0, 3.2, -2.9))
	_add_sign("到达此区域完成测试", Vector3(0, 2, -9.7))

func _add_sign(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	label.font = font
	label.font_size = 48
	label.pixel_size = 0.007
	label.position = pos
	add_child(label)

func _physics_process(dt: float) -> void:
	if not testing:
		tick(dt)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("pause"):
			set_paused(not paused)
		elif event.is_action_pressed("inventory") and not paused:
			hud.inventory.visible = not hud.inventory.visible
		elif event.is_action_pressed("interact") and not paused and not hud.inventory.visible:
			queued.append("interact")
	if event is InputEventMouseMotion and (testing or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and not paused and not hud.inventory.visible:
		player.yaw -= event.relative.x * 0.003
		player.pitch = clampf(player.pitch - event.relative.y * 0.003, -0.8, 0.5)
		update_camera()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not paused and not hud.inventory.visible:
		if not testing and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			queued.append("attack")

func tick(dt: float) -> void:
	if paused or hud.inventory.visible:
		queued.clear()
		return
	ticks += 1
	player.tick(dt, true)
	for command in queued:
		if command == "interact":
			interact()
		elif command == "attack":
			attack()
	queued.clear()
	npc.tick(dt, player)
	if door_open and player.position.z < -5 and not complete:
		complete = true
		record("objective_complete")
	update_camera()
	_refresh_ui()

func interact() -> void:
	if player.hp <= 0:
		return
	if card.visible and player.position.distance_to(Vector3(card.position.x, 0, card.position.z)) < 1.7:
		keys.append("access_card")
		card.visible = false
		hint = "获得蓝色门卡"
		record("pickup", {"item": "access_card"})
	elif player.position.distance_to(Vector3(0, 0, -3)) < 2.0:
		if "access_card" in keys:
			_set_door(not door_open)
			hint = "安全门已开启" if door_open else "安全门已关闭"
			record("door_opened" if door_open else "door_closed")
		else:
			hint = "需要蓝色门卡"
			record("door_locked")
	_refresh_ui()

func attack() -> void:
	if player.hp <= 0 or npc.hp <= 0:
		return
	var offset: Vector3 = npc.position - player.position
	var facing := Vector3.FORWARD.rotated(Vector3.UP, player.yaw)
	var ray := PhysicsRayQueryParameters3D.create(player.position + Vector3.UP, npc.position + Vector3.UP, 1)
	if offset.length() < 2.2 and facing.dot(offset.normalized()) > 0.3 and get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		npc.hp = maxf(0, npc.hp - 25)
		record("attack_hit", {"npc_hp": npc.hp})
	else:
		record("attack_missed")

func set_paused(value: bool) -> void:
	paused = value
	hud.pause_panel.visible = value
	hud.inventory.visible = false
	queued.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value or testing else Input.MOUSE_MODE_CAPTURED

func _set_door(value: bool) -> void:
	door_open = value
	door.visible = not value
	door.collision_layer = 0 if value else 1

func reset_fixture(id: String) -> bool:
	if id not in ["default", "door_locked", "npc_chase", "npc_occluded", "combat", "gallery"]:
		return false
	keys.clear()
	_set_door(false)
	card.visible = true
	complete = false
	ticks = 0
	hint = ""
	events.clear()
	queued.clear()
	player.reset_at(Vector3(0, 0.02, 5))
	npc.reset_at(Vector3(5, 0.02, -6), false)
	if id == "door_locked":
		player.reset_at(Vector3(0, 0.02, -1.5))
	elif id == "npc_chase":
		player.reset_at(Vector3(3.5, 0.02, 3))
		npc.reset_at(Vector3(3.5, 0.02, -1))
	elif id == "npc_occluded":
		player.reset_at(Vector3(3.5, 0.02, -1))
		npc.reset_at(Vector3(3.5, 0.02, -5))
	elif id == "combat":
		player.reset_at(Vector3(3.5, 0.02, 1))
		npc.reset_at(Vector3(3.5, 0.02, -0.5))
	paused = false
	hud.pause_panel.visible = false
	hud.inventory.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_view("player")
	update_camera()
	_refresh_ui()
	return true

func update_camera() -> void:
	pivot.position = player.position + Vector3(0, 1.5, 0)
	pivot.rotation = Vector3(player.pitch, player.yaw, 0)

func set_view(id: String) -> bool:
	var views := {"overview": [Vector3(7, 8, 8), Vector3(0, 0, -1)], "materials": [Vector3(-4.5, 2.8, 5), Vector3(-4.5, 1, -0.8)], "model": [Vector3(-2.5, 2.6, 5.2), Vector3(-5, 0.7, 2.1)], "npc": [Vector3(7, 2.2, -3.6), Vector3(5, 1, -6)]}
	if id == "player":
		camera.current = true
	elif id in views:
		inspection_camera.position = views[id][0]
		inspection_camera.look_at(views[id][1])
		inspection_camera.current = true
	else:
		return false
	inspection_view = id
	return true

func _refresh_ui() -> void:
	hud.refresh(player.hp, keys, complete, hint)

func record(type: String, data: Dictionary = {}) -> void:
	events.append({"tick": ticks, "type": type, "data": data})
	if events.size() > 256:
		events.pop_front()

func snapshot() -> Dictionary:
	return {"tick": ticks, "player": player.state(), "npc": npc.state(), "inventory": keys.duplicate(), "door_open": door_open, "objective_complete": complete, "paused": paused, "inventory_open": hud.inventory.visible, "view": inspection_view, "events": events.duplicate(true)}

func export_state() -> Dictionary:
	return {"version": 2, "player": player.state(), "npc": npc.state(), "inventory": keys.duplicate(), "door_open": door_open, "complete": complete, "paused": paused, "ticks": ticks, "hint": hint, "events": events.duplicate(true), "queued": Array(queued), "rng_state": str(rng.state), "rng_seed": str(rng.seed), "inventory_visible": hud.inventory.visible, "hud_visible": hud.root.visible, "view": inspection_view, "camera_position": [inspection_camera.position.x, inspection_camera.position.y, inspection_camera.position.z], "camera_rotation": [inspection_camera.rotation.x, inspection_camera.rotation.y, inspection_camera.rotation.z], "inspected_asset": inspected_asset}

func restore_state(data: Dictionary) -> String:
	var codec = preload("res://testing/state_codec.gd")
	var schema := export_state()
	# These collections have variable cardinality; validate their entries separately.
	schema.inventory = []
	schema.events = []
	schema.queued = []
	var error: String = codec.validate(data, schema)
	if not error.is_empty():
		return error
	if data.version != 2 or not data.rng_state.is_valid_int() or not data.rng_seed.is_valid_int():
		return "Unsupported state version or invalid RNG state"
	if data.view not in ["player", "overview", "materials", "model", "npc"] or data.inspected_asset != inspected_asset:
		return "View or inspected asset does not match the current world"
	for item in data.inventory:
		if item != "access_card":
			return "Unknown inventory item"
	for command in data.queued:
		if command not in ["interact", "attack"]:
			return "Unknown queued command"
	for entry in data.events:
		if not entry is Dictionary:
			return "Invalid event history"
	if data.npc.state not in ["idle", "patrol", "chase", "attack", "dead"]:
		return "Invalid NPC state"
	for actor in [data.player, data.npc]:
		if actor.animation.clip not in ["idle", "walk"] or actor.animation.time < 0 or actor.animation.time > 3600 or actor.hp < 0 or actor.hp > 100:
			return "Invalid actor health or animation"
	# Validation is complete. Apply a snapshot without resetting timers or patrol origins.
	player.position = codec.vec(data.player.position)
	player.velocity = codec.vec(data.player.velocity)
	player.hp = data.player.hp
	player.yaw = data.player.yaw
	player.pitch = data.player.pitch
	player.model.rotation.y = data.player.model_yaw
	player.animation_preview = data.player.animation.preview
	Props.restore_animation(player.animator, data.player.animation)
	npc.position = codec.vec(data.npc.position)
	npc.velocity = codec.vec(data.npc.velocity)
	npc.hp = data.npc.hp
	npc.mode = data.npc.state
	npc.cooldown = data.npc.cooldown
	npc.home = codec.vec(data.npc.home)
	npc.patrol_target = codec.vec(data.npc.patrol_target)
	npc.enabled = data.npc.enabled
	npc.last_seen = data.npc.line_of_sight
	npc.attacks = int(data.npc.attacks)
	npc.model.rotation.y = data.npc.model_yaw
	npc.animation_preview = data.npc.animation.preview
	Props.restore_animation(npc.animator, data.npc.animation)
	keys = data.inventory.duplicate()
	_set_door(data.door_open)
	card.visible = not "access_card" in keys
	complete = data.complete
	paused = data.paused
	ticks = int(data.ticks)
	hint = data.hint
	events = data.events.duplicate(true)
	queued.assign(data.queued)
	rng.seed = int(data.rng_seed)
	rng.state = int(data.rng_state)
	hud.inventory.visible = data.inventory_visible
	hud.pause_panel.visible = paused
	hud.root.visible = data.hud_visible
	set_view(data.view)
	inspection_camera.position = codec.vec(data.camera_position)
	inspection_camera.rotation = codec.vec(data.camera_rotation)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused or testing else Input.MOUSE_MODE_CAPTURED
	player.reset_physics_interpolation()
	npc.reset_physics_interpolation()
	update_camera()
	_refresh_ui()
	return ""

func save_game() -> void:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		record("save_failed")
		return
	file.store_string(JSON.stringify(export_state()))
	file.close()
	var error := DirAccess.rename_absolute(save_path + ".tmp", save_path)
	record("saved" if error == OK else "save_failed")

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		record("load_missing")
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		record("load_invalid")
		return
	var error := restore_state(data)
	record("loaded" if error.is_empty() else "load_invalid", {"reason": error})

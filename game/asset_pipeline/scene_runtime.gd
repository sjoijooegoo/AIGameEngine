extends Node3D

@export var spawn := Vector3(0,0,3)
@export var room_size := Vector3(8,3,10)
@export var exit_point := Vector3(0,0,-6)
@export var building := false
var player: CharacterBody3D
var camera: Camera3D
var door: Node3D
var door_open := false
var testing := false
var tick_count := 0
var complete := false

func _ready() -> void:
	if building:
		return
	for child in get_children():
		if child.has_meta("door"):
			door = child
	player = preload("res://scripts/player.gd").new()
	add_child(player)
	player.reset_at(spawn + Vector3(0,0.02,0))
	for action in {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"run":KEY_SHIFT}:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"run":KEY_SHIFT}[action]
			InputMap.action_add_event(action,event)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	update_camera()
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ai-session="):
				testing = true
				var bridge := preload("res://testing/bridge.gd").new()
				bridge.session = arg.trim_prefix("--ai-session=")
				bridge.adapter = preload("res://asset_pipeline/scene_adapter.gd").new(self)
				add_child(bridge)

func update_camera() -> void:
	camera.position = player.position + Vector3(0,1.6,2.8).rotated(Vector3.UP,player.yaw)
	camera.look_at(player.position + Vector3(0,1.25,0))

func _physics_process(dt: float) -> void:
	if not building and not testing:
		advance(dt)

func advance(dt: float) -> void:
	tick_count += 1
	player.tick(dt,true)
	update_camera()
	complete = complete or Vector2(player.position.x,player.position.z).distance_to(Vector2(exit_point.x,exit_point.z)) < 0.45

func _unhandled_input(event: InputEvent) -> void:
	if building:
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_E and door and player.position.distance_to(door.position)<2:
		door_open = not door_open
		door.rotation.y = -PI/2 if door_open else 0
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and (testing or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED):
		player.yaw -= event.relative.x*0.003

func observe() -> Dictionary:
	return {"tick":tick_count,"player":player.state(),"door_open":door_open,"objective_complete":complete}

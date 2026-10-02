extends Node
## Local file transport. No open port, arbitrary script evaluation, or release activation.

signal steps_finished
var session := ""
var adapter: RefCounted
var busy := false
var remaining := 0
var request_id := ""
var rendered := true
var held_keys: Array = []
var held_buttons: Array = []
var keys: Dictionary
var context: Dictionary

func _ready() -> void:
	rendered = DisplayServer.get_name() != "headless"
	var allowed := ProjectSettings.globalize_path("res://../artifacts/sessions/").simplify_path().replace("\\", "/")
	session = session.simplify_path().replace("\\", "/")
	if not session.begins_with(allowed + "/"):
		push_error("AI session must be inside artifacts/sessions")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	keys = adapter.input_keys()
	context = JSON.parse_string(FileAccess.get_file_as_string(session.path_join("context.json")))
	_write("ready.json", {"protocol": 2, "pid": OS.get_process_id(), "godot": Engine.get_version_info().string, "rendered": rendered, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name() if rendered else "headless", "adapter": adapter.describe(), "inputs": keys.keys(), "commands": ["describe", "state", "ui", "reset", "act", "step", "click", "capture", "sequence", "checkpoint", "restore", "animation", "view", "resize", "audit", "asset", "quit"]})

func _process(_dt: float) -> void:
	var path := session.path_join("request.json")
	if busy or not FileAccess.file_exists(path):
		return
	var raw := FileAccess.get_file_as_string(path)
	# A transient Windows sharing violation can expose the name before it is readable.
	if raw.is_empty():
		return
	busy = true
	var request = JSON.parse_string(raw)
	DirAccess.remove_absolute(path)
	if not request is Dictionary:
		busy = false
		return
	request_id = str(request.get("id", ""))
	if not request_id.is_valid_int():
		busy = false
		return
	_handle(request)

func _physics_process(_dt: float) -> void:
	if remaining > 0:
		adapter.advance(1.0 / 60.0)
		remaining -= 1
		if remaining == 0:
			steps_finished.emit()

func _handle(request: Dictionary) -> void:
	if not request.get("args", {}) is Dictionary:
		_reply({}, "args must be an object")
		return
	var args: Dictionary = request.get("args", {})
	if request.get("command") in ["act", "step", "sequence"]:
		if not args.get("keys", []) is Array or not args.get("buttons", []) is Array:
			_reply({}, "keys and buttons must be arrays")
			return
		if args.has("mouse"):
			if not args.mouse is Array or args.mouse.size() != 2:
				_reply({}, "mouse must contain two finite numbers")
				return
			for value in args.mouse:
				if not typeof(value) in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
					_reply({}, "mouse must contain two finite numbers")
					return
	match request.get("command", ""):
		"describe":
			_reply(adapter.describe())
		"state":
			_reply(adapter.observe())
		"ui":
			_reply(adapter.inspect_ui())
		"reset":
			_release_inputs()
			var valid: bool = adapter.reset(str(args.get("fixture", "default")), int(args.get("seed", 12345)))
			await get_tree().physics_frame
			await get_tree().process_frame
			_reply(adapter.observe(), "" if valid else "Unknown fixture")
		"act", "step":
			var frames := int(args.get("frames", 1))
			if frames < 1 or frames > 600:
				_reply({}, "frames must be 1..600")
				return
			for key in args.get("keys", []):
				if str(key).to_upper() not in keys:
					_reply({}, "Unsupported key")
					return
			for button in args.get("buttons", []):
				if button not in ["left", "right"]:
					_reply({}, "Unsupported button")
					return
			for key in args.get("keys", []):
				var k := str(key).to_upper()
				held_keys.append(k)
				_key(k, true)
			if args.has("mouse"):
				var motion := InputEventMouseMotion.new()
				motion.relative = get_viewport().get_final_transform().basis_xform(Vector2(args.mouse[0], args.mouse[1]))
				Input.parse_input_event(motion)
			for button in args.get("buttons", []):
				held_buttons.append(button)
				_mouse(button, true, Vector2(640, 360))
			Input.flush_buffered_events()
			remaining = frames
			await steps_finished
			_release_inputs()
			await get_tree().process_frame
			_reply(adapter.observe())
		"click":
			var id := str(args.get("control", ""))
			var control: Control = adapter.find_control(id)
			if control == null:
				_reply({}, "Unknown control")
				return
			if not control is Button or not control.is_visible_in_tree() or control.disabled:
				_reply({}, "Control must be a visible enabled button")
				return
			# Hit-test through the viewport. Do not emit pressed or call callbacks directly.
			var point := control.get_global_rect().get_center()
			_mouse("left", true, point)
			await get_tree().process_frame
			_mouse("left", false, point)
			await get_tree().process_frame
			_reply(adapter.observe())
		"capture":
			if not rendered:
				_reply({}, "Visual capture requires a rendered session, not headless")
				return
			var name := str(args.get("name", "capture"))
			if not _valid_name(name):
				_reply({}, "Invalid capture name")
				return
			var result: Dictionary = await _capture(name)
			_reply(result, str(result.get("error", "")))
		"checkpoint", "restore":
			var name := str(args.get("name", "checkpoint"))
			if "checkpoint" not in adapter.describe().capabilities or not _valid_name(name):
				_reply({}, "Invalid checkpoint name or unsupported adapter")
				return
			if request.command == "checkpoint":
				var data := {"format": 1, "game_id": adapter.describe().game_id, "build_id": context.build_id, "payload": adapter.save_state()}
				_write(name + ".checkpoint.json", data)
				_reply({"path": session.path_join(name + ".checkpoint.json"), "state": adapter.observe()})
			else:
				var path := session.path_join(name + ".checkpoint.json")
				if not FileAccess.file_exists(path):
					_reply({}, "Checkpoint not found")
					return
				var data = JSON.parse_string(FileAccess.get_file_as_string(path))
				if not data is Dictionary or data.get("format") != 1 or data.get("game_id") != adapter.describe().game_id or data.get("build_id") != context.build_id or not data.get("payload") is Dictionary:
					_reply({}, "Checkpoint version, game or source fingerprint mismatch")
					return
				_release_inputs()
				var error: String = adapter.restore_state(data.payload)
				await get_tree().physics_frame
				await get_tree().process_frame
				_reply(adapter.observe(), error)
		"animation":
			var error: String = adapter.sample_animation(args)
			await get_tree().process_frame
			_reply(adapter.observe(), error)
		"sequence":
			var name := str(args.get("name", "sequence"))
			var count := int(args.get("count", 12))
			var interval := int(args.get("interval", 5))
			if not rendered or not _valid_name(name) or count < 2 or count > 120 or interval < 1 or interval > 60 or count * interval > 1200:
				_reply({}, "Sequence needs rendering, count 2..120, interval 1..60 and at most 1200 steps")
				return
			for key in args.get("keys", []):
				if str(key).to_upper() not in keys:
					_reply({}, "Unsupported sequence key")
					return
			for key in args.get("keys", []):
				var k := str(key).to_upper()
				held_keys.append(k)
				_key(k, true)
			Input.flush_buffered_events()
			var frames: Array = []
			# Every captured pose is frozen while drawing; render waits cannot advance simulation.
			for i in range(count):
				if i > 0:
					remaining = interval
					await steps_finished
				var result: Dictionary = await _capture(name + "_%03d" % i)
				if result.has("error"):
					_release_inputs()
					_reply({}, result.error)
					return
				frames.append({"index": i, "simulation_time": float(i * interval) / 60.0, "path": result.path, "state": adapter.observe()})
			var result := {"name": name, "interval": interval, "fps": 60.0 / interval, "frames": frames}
			_release_inputs()
			_write(name + ".sequence.json", result)
			_reply({"path": session.path_join(name + ".sequence.json"), "count": count})
		"view":
			var error: String = adapter.configure_view(args)
			await get_tree().process_frame
			_reply(adapter.observe(), error)
		"resize":
			var width := int(args.get("width", 1280))
			var height := int(args.get("height", 720))
			if width < 640 or width > 3840 or height < 360 or height > 2160:
				_reply({}, "Unsupported dimensions")
				return
			get_window().size = Vector2i(width, height)
			await get_tree().process_frame
			await get_tree().process_frame
			_reply(adapter.inspect_ui())
		"audit":
			var meshes: Array = []
			_audit_node(adapter.game, meshes)
			_reply({"meshes": meshes, "mesh_count": meshes.size(), "performance": {"fps": Engine.get_frames_per_second(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}})
		"asset":
			var path := str(args.get("path", ""))
			if not path.begins_with("res://assets/") or ".." in path or path.get_extension() not in ["glb", "gltf", "tscn"] or not ResourceLoader.exists(path):
				_reply({}, "Expected an imported scene under res://assets/")
				return
			var error: String = adapter.load_asset(path)
			await get_tree().process_frame
			_reply({"asset": path}, error)
		"quit":
			_release_inputs()
			_reply({"quitting": true})
			get_tree().quit()
		_:
			_reply({}, "Unknown command")

func _key(key: String, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keys[key]
	event.keycode = keys[key]
	event.pressed = pressed
	Input.parse_input_event(event)

func _mouse(button: String, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT if button == "left" else MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = get_viewport().get_final_transform() * point
	event.global_position = event.position
	Input.parse_input_event(event)

func _release_inputs() -> void:
	for key in held_keys:
		_key(key, false)
	for button in held_buttons:
		_mouse(button, false, Vector2(640, 360))
	held_keys.clear()
	held_buttons.clear()
	Input.flush_buffered_events()

func _valid_name(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for ch in value:
		if not ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

func _write(name: String, value: Dictionary) -> void:
	var path := session.path_join(name)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write AI session response")
		return
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func _reply(result: Dictionary, error: String = "") -> void:
	_write("response_" + request_id + ".json", {"id": request_id, "ok": error.is_empty(), "result": result, "error": error})
	busy = false

func _audit_node(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh:
		var surfaces: Array = []
		for index in range(node.mesh.get_surface_count()):
			var mat: Material = node.get_active_material(index)
			var arrays: Array = node.mesh.surface_get_arrays(index)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var uv = arrays[Mesh.ARRAY_TEX_UV]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var item := {"material": mat.get_class() if mat else "MISSING", "vertices": vertices.size() if vertices != null else 0, "uv_count": uv.size() if uv != null else 0, "triangles": (indices.size() if indices != null and indices.size() > 0 else vertices.size()) / 3}
			if mat is BaseMaterial3D:
				item["roughness"] = mat.roughness
				item["metallic"] = mat.metallic
				if mat.albedo_texture:
					item["albedo_texture"] = {"path": mat.albedo_texture.resource_path, "width": mat.albedo_texture.get_width(), "height": mat.albedo_texture.get_height()}
			surfaces.append(item)
		var box: AABB = node.get_aabb()
		result.append({"path": str(adapter.game.get_path_to(node)), "aabb_size": [box.size.x, box.size.y, box.size.z], "visible": node.is_visible_in_tree(), "surfaces": surfaces})
	for child in node.get_children():
		_audit_node(child, result)

func _capture(name: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := session.path_join(name + ".png")
	if image.save_png(path) != OK:
		return {"error": "PNG write failed"}
	_write(name + ".state.json", {"state": adapter.observe(), "ui": adapter.inspect_ui(), "size": [image.get_width(), image.get_height()]})
	return {"path": path, "width": image.get_width(), "height": image.get_height()}

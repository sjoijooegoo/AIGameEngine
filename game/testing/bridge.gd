extends Node
## Local file transport. No open port, arbitrary script evaluation, or release activation.

signal steps_finished
var session := ""
var world: Node
var busy := false
var remaining := 0
var request_id := ""
var rendered := true
var held_keys: Array = []
var held_buttons: Array = []
const KEYS := {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D, "E": KEY_E, "TAB": KEY_TAB, "ESC": KEY_ESCAPE, "SHIFT": KEY_SHIFT}

func _ready() -> void:
	rendered = DisplayServer.get_name() != "headless"
	var allowed := ProjectSettings.globalize_path("res://../artifacts/sessions/").simplify_path().replace("\\", "/")
	session = session.simplify_path().replace("\\", "/")
	if not session.begins_with(allowed + "/"):
		push_error("AI session must be inside artifacts/sessions")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_write("ready.json", {"protocol": 1, "pid": OS.get_process_id(), "godot": Engine.get_version_info().string, "rendered": rendered, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name() if rendered else "headless", "commands": ["state", "ui", "reset", "act", "step", "click", "capture", "view", "resize", "audit", "asset", "quit"]})

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
		world.tick(1.0 / 60.0)
		remaining -= 1
		if remaining == 0:
			steps_finished.emit()

func _handle(request: Dictionary) -> void:
	var args: Dictionary = request.get("args", {})
	match request.get("command", ""):
		"state":
			_reply(world.snapshot())
		"ui":
			_reply(world.hud.inspect())
		"reset":
			_release_inputs()
			var valid: bool = world.reset_fixture(str(args.get("fixture", "default")))
			await get_tree().physics_frame
			await get_tree().process_frame
			_reply(world.snapshot(), "" if valid else "Unknown fixture")
		"act", "step":
			var frames := int(args.get("frames", 1))
			if frames < 1 or frames > 600:
				_reply({}, "frames must be 1..600")
				return
			for key in args.get("keys", []):
				if str(key).to_upper() not in KEYS:
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
			_reply(world.snapshot())
		"click":
			var id := str(args.get("control", ""))
			if not world.hud.controls.has(id):
				_reply({}, "Unknown control")
				return
			var control: Control = world.hud.controls[id]
			if not control is Button or not control.is_visible_in_tree() or control.disabled:
				_reply({}, "Control must be a visible enabled button")
				return
			# Hit-test through the viewport. Do not emit pressed or call callbacks directly.
			var point := control.get_global_rect().get_center()
			_mouse("left", true, point)
			await get_tree().process_frame
			_mouse("left", false, point)
			await get_tree().process_frame
			_reply(world.snapshot())
		"capture":
			if not rendered:
				_reply({}, "Visual capture requires a rendered session, not headless")
				return
			var name := str(args.get("name", "capture"))
			if not _valid_name(name):
				_reply({}, "Invalid capture name")
				return
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var path := session.path_join(name + ".png")
			var error := image.save_png(path)
			_write(name + ".state.json", {"state": world.snapshot(), "ui": world.hud.inspect(), "size": [image.get_width(), image.get_height()]})
			_reply({"path": path, "width": image.get_width(), "height": image.get_height()}, "" if error == OK else "PNG write failed")
		"view":
			var valid: bool = world.set_view(str(args.get("name", "player")))
			if args.has("hud"):
				world.hud.root.visible = bool(args.hud)
			if args.has("orbit_degrees") and world.inspection_view == "model":
				var center := Vector3(-5, 0.8, 2.1)
				world.inspection_camera.position = center + Vector3(0, 1.4, 2.5).rotated(Vector3.UP, deg_to_rad(float(args.orbit_degrees)))
				world.inspection_camera.look_at(center)
			await get_tree().process_frame
			_reply(world.snapshot(), "" if valid else "Unknown view")
		"resize":
			var width := int(args.get("width", 1280))
			var height := int(args.get("height", 720))
			if width < 640 or width > 3840 or height < 360 or height > 2160:
				_reply({}, "Unsupported dimensions")
				return
			get_window().size = Vector2i(width, height)
			await get_tree().process_frame
			await get_tree().process_frame
			_reply(world.hud.inspect())
		"audit":
			var meshes: Array = []
			_audit_node(world, meshes)
			_reply({"meshes": meshes, "mesh_count": meshes.size(), "performance": {"fps": Engine.get_frames_per_second(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}})
		"asset":
			var path := str(args.get("path", ""))
			if not path.begins_with("res://assets/") or ".." in path or path.get_extension() not in ["glb", "gltf", "tscn"] or not ResourceLoader.exists(path):
				_reply({}, "Expected an imported scene under res://assets/")
				return
			var resource = load(path)
			if not resource is PackedScene:
				_reply({}, "Asset is not a scene")
				return
			var instance: Node = resource.instantiate()
			if not instance is Node3D:
				instance.free()
				_reply({}, "Asset root must be Node3D")
				return
			var old: Node = world.gallery.get_node_or_null("ImportedCrate")
			if old:
				world.gallery.remove_child(old)
				old.queue_free()
			instance.name = "ImportedCrate"
			instance.position = Vector3(-5, 0.65, 2.1)
			world.gallery.add_child(instance)
			world.set_view("model")
			await get_tree().process_frame
			_reply({"asset": path})
		"quit":
			_release_inputs()
			_reply({"quitting": true})
			get_tree().quit()
		_:
			_reply({}, "Unknown command")

func _key(key: String, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEYS[key]
	event.keycode = KEYS[key]
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
		result.append({"path": str(world.get_path_to(node)), "aabb_size": [box.size.x, box.size.y, box.size.z], "visible": node.is_visible_in_tree(), "surfaces": surfaces})
	for child in node.get_children():
		_audit_node(child, result)

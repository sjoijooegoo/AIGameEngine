extends "res://testing/game_adapter.gd"

func describe() -> Dictionary:
	return {"adapter_version": 1, "game_id": "bank_lab", "capabilities": ["view", "asset", "animation", "checkpoint"], "fixtures": ["default", "door_locked", "npc_chase", "npc_occluded", "combat", "gallery"], "views": ["player", "overview", "materials", "model", "npc"], "entities": ["player", "npc"], "state_version": 2}

func input_keys() -> Dictionary:
	return {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D, "E": KEY_E, "TAB": KEY_TAB, "ESC": KEY_ESCAPE, "SHIFT": KEY_SHIFT}

func advance(dt: float) -> void:
	game.tick(dt)

func observe() -> Dictionary:
	return game.snapshot()

func inspect_ui() -> Dictionary:
	return game.hud.inspect()

func find_control(id: String) -> Control:
	return game.hud.controls.get(id)

func reset(fixture: String, seed_value: int) -> bool:
	if fixture not in describe().fixtures:
		return false
	game.rng.seed = seed_value
	return game.reset_fixture(fixture)

func configure_view(options: Dictionary) -> String:
	if not game.set_view(str(options.get("name", "player"))):
		return "Unknown view"
	if options.has("hud"):
		game.hud.root.visible = bool(options.hud)
	if options.has("orbit_degrees") and game.inspection_view == "model":
		var center := Vector3(-5, 0.8, 2.1)
		game.inspection_camera.position = center + Vector3(0, 1.4, 2.5).rotated(Vector3.UP, deg_to_rad(float(options.orbit_degrees)))
		game.inspection_camera.look_at(center)
	return ""

func load_asset(path: String) -> String:
	var resource = load(path)
	if not resource is PackedScene:
		return "Asset is not a scene"
	var instance: Node = resource.instantiate()
	if not instance is Node3D:
		instance.free()
		return "Asset root must be Node3D"
	var old: Node = game.gallery.get_node_or_null("ImportedCrate")
	if old:
		game.gallery.remove_child(old)
		old.queue_free()
	instance.name = "ImportedCrate"
	instance.position = Vector3(-5, 0.65, 2.1)
	game.gallery.add_child(instance)
	game.inspected_asset = path
	game.set_view("model")
	return ""

func sample_animation(options: Dictionary) -> String:
	var entity := str(options.get("entity", "player"))
	if entity not in ["player", "npc"]:
		return "Unknown animated entity"
	var actor: Node = game.player if entity == "player" else game.npc
	var clip := str(options.get("clip", "walk"))
	if not actor.animator.has_animation(clip):
		return "Unknown animation clip"
	var at_time := float(options.get("time", 0))
	if not is_finite(at_time) or at_time < 0 or at_time > 3600:
		return "Animation time must be 0..3600 seconds"
	actor.animation_preview = bool(options.get("preview", true))
	actor.animator.play(clip)
	actor.animator.seek(at_time, true)
	return ""

func save_state() -> Dictionary:
	return game.export_state()

func restore_state(data: Dictionary) -> String:
	return game.restore_state(data)

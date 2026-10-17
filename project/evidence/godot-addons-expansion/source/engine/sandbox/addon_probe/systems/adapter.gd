extends "res://addons/ai_engine/testing/game_adapter.gd"

func describe() -> Dictionary:
	return {"adapter_version": 1, "game_id": "addon_systems", "capabilities": [], "fixtures": [], "views": [], "entities": ["terminal", "ai"], "checkpoint_note": "Dialogue and BT internal checkpoint state not integrated; fresh sessions only"}

func input_keys() -> Dictionary:
	return {"E": KEY_E, "K": KEY_K, "F": KEY_F, "SPACE": KEY_SPACE, "1": KEY_1, "2": KEY_2}

func advance(dt: float) -> void:
	game.tick(dt)

func observe() -> Dictionary:
	return game.observe()

func find_control(id: String) -> Control:
	return game.controls.get(id)

func inspect_ui() -> Dictionary:
	var result := {}
	var viewport: Rect2 = game.get_viewport_rect()
	for id in game.controls:
		var control: Control = game.controls[id]
		var rect := control.get_global_rect()
		result[id] = {"text": control.text, "visible": control.visible, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "inside_viewport": viewport.encloses(rect)}
	return {"viewport": [viewport.size.x, viewport.size.y], "controls": result}

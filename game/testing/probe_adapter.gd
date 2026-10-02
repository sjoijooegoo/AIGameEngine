extends "res://testing/game_adapter.gd"

func describe() -> Dictionary:
	return {"adapter_version": 1, "game_id": "counter_probe", "capabilities": ["checkpoint"], "fixtures": ["default"], "views": [], "entities": ["counter"], "state_version": 1}

func input_keys() -> Dictionary:
	return {"SPACE": KEY_SPACE}

func advance(_dt: float) -> void:
	game.ticks += 1

func observe() -> Dictionary:
	return {"count": game.count, "tick": game.ticks}

func reset(fixture: String, seed_value: int) -> bool:
	if fixture != "default":
		return false
	game.count = 0
	game.ticks = 0
	game.rng.seed = seed_value
	return true

func save_state() -> Dictionary:
	return {"version": 1, "count": game.count, "tick": game.ticks, "rng_state": str(game.rng.state)}

func restore_state(data: Dictionary) -> String:
	if data.get("version") != 1 or not data.get("rng_state", "").is_valid_int() or not data.has_all(["count", "tick"]):
		return "Invalid counter checkpoint"
	game.count = int(data.count)
	game.ticks = int(data.tick)
	game.rng.state = int(data.rng_state)
	return ""

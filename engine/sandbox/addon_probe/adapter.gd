extends "res://addons/ai_engine/testing/game_adapter.gd"

func describe() -> Dictionary:
	return {"adapter_version": 1, "game_id": "addon_probe", "capabilities": [], "fixtures": [], "views": [], "entities": ["player", "follow", "aim"], "checkpoint_note": "Plugin internal state serialization is not implemented; launch a fresh session for each independent test"}

func input_keys() -> Dictionary:
	return {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D, "F": KEY_F, "G": KEY_G}

func advance(dt: float) -> void:
	game.tick(dt)

func observe() -> Dictionary:
	return game.observe()

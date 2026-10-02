extends "res://testing/game_adapter.gd"

func describe() -> Dictionary:
	return {"adapter_version":1,"game_id":"assembled_room","capabilities":[],"fixtures":["default"],"views":[],"entities":["player","door"],"state_version":1}

func input_keys() -> Dictionary:
	return {"W":KEY_W,"A":KEY_A,"S":KEY_S,"D":KEY_D,"E":KEY_E,"SHIFT":KEY_SHIFT,"ESC":KEY_ESCAPE}

func advance(dt: float) -> void:
	game.advance(dt)

func observe() -> Dictionary:
	return game.observe()

func reset(fixture: String, _seed: int) -> bool:
	if fixture != "default":
		return false
	game.player.reset_at(game.spawn+Vector3(0,0.02,0))
	game.door_open=false
	game.door.rotation.y=0
	game.complete=false
	game.tick_count=0
	return true

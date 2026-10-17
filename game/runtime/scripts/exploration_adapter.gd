extends "res://addons/ai_engine/testing/game_adapter.gd"

func describe() -> Dictionary:
	return {"adapter_version":1,"game_id":"bank_exploration","state_version":4,"capabilities":["ui"],"fixtures":game.fixtures.keys(),"views":["player","grip_side","grip_top","grip_palm","grip_back"],"entities":["player","doors","infected","firearms","ui"]}

func input_keys() -> Dictionary:
	return {"W":KEY_W,"A":KEY_A,"S":KEY_S,"D":KEY_D,"SHIFT":KEY_SHIFT,"E":KEY_E,"F":KEY_F,"R":KEY_R,"1":KEY_1,"2":KEY_2,"3":KEY_3,"4":KEY_4,"F8":KEY_F8,"F9":KEY_F9,"ESC":KEY_ESCAPE,"TAB":KEY_TAB,"ENTER":KEY_ENTER,"UP":KEY_UP,"DOWN":KEY_DOWN,"LEFT":KEY_LEFT,"RIGHT":KEY_RIGHT}

func advance(dt: float) -> void:
	game.advance(dt)

func observe() -> Dictionary:
	var state: Dictionary=game.observe()
	state["grip"]=game.held_weapon.grip_state()
	state["ui"]=game.ui.observe()
	state["lighting"]=game.indoor_lights.observe()
	state["indirect_light"]=game.indirect_stats
	state["viewmodel_lighting"]=game.viewmodel_lighting.observe()
	state["flashlight_lighting"]=game.flashlight_lighting.observe()
	return state

func reset(fixture: String, _seed: int) -> bool:
	return game.reset_fixture(fixture)

func configure_view(options: Dictionary) -> String:
	if options.get("name","player") not in ["player","grip_side","grip_top","grip_palm","grip_back"]:
		return "Unsupported inspection view"
	game.held_weapon.inspect_grip(options.get("name","player"))
	return ""

func inspect_ui() -> Dictionary:
	return game.ui.inspect()

func find_control(id: String) -> Control:
	return game.ui.controls.get(id)

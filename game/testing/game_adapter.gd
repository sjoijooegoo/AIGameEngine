extends RefCounted
## Versioned seam between any game and the generic transport. No bank-specific fields.

var game: Node

func _init(root: Node) -> void:
	game = root

func describe() -> Dictionary:
	return {"adapter_version": 1, "game_id": "abstract", "capabilities": [], "fixtures": [], "views": [], "entities": []}

func input_keys() -> Dictionary:
	return {}

func advance(_dt: float) -> void:
	pass

func observe() -> Dictionary:
	return {}

func inspect_ui() -> Dictionary:
	return {"viewport": [0, 0], "controls": {}}

func find_control(_id: String) -> Control:
	return null

func reset(_fixture: String, _seed: int) -> bool:
	return false

func configure_view(_options: Dictionary) -> String:
	return "View inspection is unsupported by this adapter"

func load_asset(_path: String) -> String:
	return "Asset inspection is unsupported by this adapter"

func sample_animation(_options: Dictionary) -> String:
	return "Animation inspection is unsupported by this adapter"

func save_state() -> Dictionary:
	return {}

func restore_state(_data: Dictionary) -> String:
	return "State restoration is unsupported by this adapter"

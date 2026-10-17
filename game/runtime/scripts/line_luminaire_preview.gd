extends "res://scripts/exploration.gd"
## Selected only by the Line Luminaire Preview export feature.
var line_preview=preload("res://scripts/line_luminaire_profile.gd").new()

func _ready() -> void:
	super._ready()
	if not indirect_stats.get("loaded",false):
		push_error("Line luminaire preview requires the reference v46 indirect bake")
		get_tree().quit(1);return
	line_preview.setup(self)
	DisplayServer.window_set_title("银行危机 · 手电柔光收窄调暗 v52")
	var configuration: Dictionary=line_preview.observe()
	print("BANK_LINE_LUMINAIRES ",JSON.stringify({"fixtures":configuration.fixture_count,"emitters":configuration.emitters,"shadow_triangles":configuration.shadow_triangles,"indirect":configuration.indirect}))

func advance(dt: float) -> void:
	super.advance(dt)
	if is_instance_valid(line_preview.world):line_preview.update_viewmodel()

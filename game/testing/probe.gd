extends Node
## A deliberately non-bank world proving the adapter contract works independently.

var count := 0
var ticks := 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ai-session="):
				var bridge := preload("res://testing/bridge.gd").new()
				bridge.session = arg.trim_prefix("--ai-session=")
				bridge.adapter = preload("res://testing/probe_adapter.gd").new(self)
				add_child(bridge)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_SPACE and event.pressed and not event.echo:
		count += rng.randi_range(1, 10)

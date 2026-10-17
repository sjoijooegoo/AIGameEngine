extends Node3D

func _ready() -> void:
	var server:=OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()
	var world=preload("res://coop/world.gd").new();world.visual=not server;add_child(world)
	var session=preload("res://coop/session.gd").new();session.visual=not server;add_child(session)

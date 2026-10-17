extends RefCounted
## Godot 4.7 light-pairing workaround (upstream issue #121989). Detach with
## the OLD mask before changing layers, then reattach with the NEW mask.
## Plain layer mutation can leave stale light pairs and corrupt PCSS counts.
static func assign(visual: VisualInstance3D, mask: int) -> void:
	if visual.layers==mask:return
	if not visual.is_inside_tree():visual.layers=mask;return
	var scenario: RID=visual.get_world_3d().scenario
	RenderingServer.instance_set_scenario(visual.get_instance(),RID())
	visual.layers=mask
	RenderingServer.instance_set_scenario(visual.get_instance(),scenario)

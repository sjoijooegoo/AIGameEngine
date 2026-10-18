extends "coop_combat_performance.gd"
## Extra wall-clock tick spacing for the resource-limited Linux benchmark.
## Inherits the existing bounded debug-only input and fixture protocol.
func boot() -> void:
	await super.boot()
	if "--lean-load-client" in OS.get_cmdline_user_args():
		assert(not game.is_host, "Lean presentation is forbidden on the measured server")
		var presentation=load(get_script().resource_path.get_base_dir().path_join("wsl_load_presentation.gd")).new()
		presentation.world=game.world
		game.presentation=presentation

func _physics_process(dt: float) -> bool:
	var started := Time.get_ticks_usec()
	var result := super._physics_process(dt)
	if measuring and not game.world.profiler.ticks.is_empty():
		game.world.profiler.ticks[-1].started_usec = started
	return result

extends "wsl_coop_performance.gd"
## Diagnostic only: preserve the full living crowd using ordinary movement,
## aim, struggle and zero-damage right-click shoves. No gunfire or HP mutation.
## This complements gunfire/corpse combat; it is not a shooting-flow test.
func mouse_button(code: int, down: bool) -> void:
	if code != MOUSE_BUTTON_LEFT:
		super.mouse_button(code, down)

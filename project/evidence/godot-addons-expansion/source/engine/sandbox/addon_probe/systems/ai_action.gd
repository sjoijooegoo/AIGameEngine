@tool
extends BTAction
## Small fixture action. No production navigation or checkpoint claim.
func _tick(delta: float) -> Status:
	agent.ai_ticks += 1
	agent.ai_mode = "警戒" if blackboard.get_var("alert", false) else "巡逻"
	agent.ai_progress = fmod(agent.ai_progress + delta * (0.55 if blackboard.get_var("alert", false) else 0.15), 1.0)
	return RUNNING

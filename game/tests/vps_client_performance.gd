extends "wsl_coop_performance.gd"
## Native ENet telemetry for real WAN sampling; no injected latency.
func _physics_process(dt: float) -> bool:
	if game!=null and (run_config.is_empty() or Time.get_unix_time_from_system()<float(run_config.start)):
		game.world.advance(dt)
		return false
	return super._physics_process(dt)

func _process(dt: float) -> bool:
	var result:=super._process(dt)
	if measuring and not telemetry.is_empty():
		telemetry[-1].buffer=game.snapshot_buffer.observe()
		telemetry[-1].delta=game.snapshot_delta.observe()
		telemetry[-1].retrying=game.recovery.retrying
		telemetry[-1].peer_id=game.local_id
	if measuring and not telemetry.is_empty() and game.peer and game.multiplayer.get_peers().has(1):
		var peer=game.peer.get_peer(1)
		telemetry[-1].rtt_ms=peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		telemetry[-1].rtt_variance_ms=peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)
		telemetry[-1].throttle=peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)
	return result

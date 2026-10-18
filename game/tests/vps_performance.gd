extends "wsl_coop_performance.gd"
## SSH-controlled validation only. No remote evaluation or public test API.
func _physics_process(dt: float) -> bool:
	# WAN leases, ENet RTT/throttle and assembly expiry use real wall time.
	# Keep the world live while the controller reads results or stages a run.
	if game!=null and (run_config.is_empty() or Time.get_unix_time_from_system()<float(run_config.start)):
		game.world.advance(dt)
		return false
	return super._physics_process(dt)

func _process(dt: float) -> bool:
	var result:=super._process(dt)
	if measuring and not telemetry.is_empty() and game.peer:
		var network: Dictionary={}
		for id in game.multiplayer.get_peers():
			var peer=game.peer.get_peer(id)
			network[str(id)]={"rtt":peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),"throttle":peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),"reliable_loss_ratio":peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)/ENetPacketPeer.PACKET_LOSS_SCALE}
		telemetry[-1].peers=network
	return result

func _initialize() -> void:
	assert(OS.is_debug_build())
	var found:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--validation-overlay="):
			assert(ProjectSettings.load_resource_pack(arg.trim_prefix("--validation-overlay="),true))
			found=true
	assert(found,"Validation requires exact bake source bytes from the paired release")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--candidate-overlay="):
			assert(ProjectSettings.load_resource_pack(arg.trim_prefix("--candidate-overlay="),true))
			var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://candidate_manifest.json"))
			for resource in manifest:
				assert(FileAccess.get_sha256(resource)==manifest[resource])
				assert(load(resource).source_code==FileAccess.get_file_as_string(resource),"Candidate script remap did not load exact source: "+resource)
	super._initialize()

func boot() -> void:
	await super.boot()
	assert(game.world.indirect_stats.get("loaded",false),"Validation must use the current baked scene")
	write_json("validation.json",{"bake":game.world.indirect_stats,"debug":OS.is_debug_build(),"engine":Engine.get_version_info().string,"protocol":game.PROTOCOL,
		"candidate":JSON.parse_string(FileAccess.get_file_as_string("res://candidate_manifest.json")) if FileAccess.file_exists("res://candidate_manifest.json") else {}})

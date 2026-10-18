extends "bank_coop_driver.gd"
## Read-only compact telemetry. Gameplay commands stay in the normal input driver.
var recording := false
var records: Array=[]
var fixture_barrier: FixtureBarrier

class FixtureBarrier extends Node:
	# Test setup only: ordered behind the production reset on reliable channel 0.
	# Receiving a newer unreliable world packet does NOT prove reset arrived.
	var serial := 0
	@rpc("authority","call_local","reliable",0)
	func mark(value: int) -> void:
		serial=value

func boot() -> void:
	super.boot()
	fixture_barrier=FixtureBarrier.new();fixture_barrier.name="NetworkFixtureBarrier";root.add_child(fixture_barrier)

func _process(dt: float) -> bool:
	var result:=super._process(dt)
	if recording and game!=null and records.size()<7200:
		var sample:={"time_ms":Time.get_unix_time_from_system()*1000.0,"tick":game.tick,"bank_tick":game.bank_tick,"players":{},"shots":{},"rtt_ms":0.0,"throttle":32.0,"world_age_ms":Time.get_ticks_msec()-game.last_bank_received_msec if game.last_bank_received_msec>0 else -1,"wire_bytes":game.wire_bytes}
		sample.preview_shots=game.preview_count;sample.prediction=game.prediction.observe()
		for id in game.players:
			var body=game.players[id]
			sample.players[str(id)]={"position":[body.position.x,body.position.y,body.position.z],"motion":body.motion}
			sample.shots[str(id)]=game.contexts[id].weapon.shots if game.is_host else game.team.get(id,{}).get("shots",-1)
		if game.peer and not game.is_host and game.multiplayer.get_peers().has(1):
			var peer=game.peer.get_peer(1)
			sample.rtt_ms=peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			sample.throttle=peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)
		records.append(sample)
	return result

func execute(request: Dictionary) -> void:
	if request.command=="tcp_only_fixture":
		# Bounded transport setup: an unused UDP endpoint with a live TCP carrier.
		# The carrier still forwards only to this bank server's original UDP port.
		assert(game.is_host and is_instance_valid(game.server_tunnel))
		var port:=int(request.get("port",0));assert(port>=1024 and port<=65535)
		game.server_tunnel.listener.stop()
		assert(game.server_tunnel.listener.listen(port,"127.0.0.2")==OK)
		write_json("response.json",{"id":request.id,"result":{"port":port}});busy=false;return
	if request.command=="cut_tcp":
		# Transport fault injection only; normal production recovery handles it.
		assert(not game.is_host and is_instance_valid(game.client_tunnel))
		for link in game.client_tunnel.links:link.tcp.disconnect_from_host()
		write_json("response.json",{"id":request.id,"result":{"cut":true}});busy=false;return
	if request.command=="fixture":
		var recovery_fixture: bool=request.get("name","")=="recovery_state"
		if recovery_fixture:request=request.duplicate();request.name="firearms_range"
		await super.execute(request)
		if recovery_fixture:
			for context in game.contexts.values():context.hp=73
		if game.is_host:fixture_barrier.mark.rpc(fixture_barrier.serial+1)
		return
	if request.command=="record_start":
		records.clear();recording=true;write_json("response.json",{"id":request.id,"result":{}});busy=false;return
	if request.command=="record_stop":
		recording=false;write_json("response.json",{"id":request.id,"result":{"samples":records}});busy=false;return
	if request.command!="net_state":await super.execute(request);return
	var value:={"tick":game.tick,"bank_tick":game.bank_tick,"id":game.local_id,"status":game.status,"started":game.started,"round":game.round_id if game.is_host else game.received_round,"input":game.input_enabled,"players":{},"weapons":{},"network":{},"wire_bytes":game.wire_bytes,"tick_usec":game.server_tick_usec,"world_age_ms":Time.get_ticks_msec()-game.last_bank_received_msec if game.last_bank_received_msec>0 else -1}
	for id in game.players:
		var body=game.players[id]
		value.players[str(id)]={"position":[body.position.x,body.position.y,body.position.z],"motion":body.motion,"ack":body.last_sequence,"last_input_tick":body.last_input_tick,"queued_inputs":body.commands.size()}
		var state: Dictionary=game.contexts[id].state() if game.is_host else game.team.get(id,{})
		value.weapons[str(id)]={"shots":state.get("shots",-1),"ammo":state.get("ammo",{}),"hp":state.get("hp",-1)}
	if game.peer:
		for id in game.multiplayer.get_peers():
			var peer=game.peer.get_peer(id)
			value.network[str(id)]={"rtt_ms":peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),"rtt_variance_ms":peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE),"throttle":peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),"throttle_limit":peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT)}
	value.door=game.world.doors.g_inner.progress
	value.prediction=game.prediction.observe();value.assembly=game.snapshot_buffer.observe();value.preview_shots=game.preview_count
	value.network_text=game.network_summary()
	value.transport=game.peer!=null
	value.carrier=game.transport_mode
	value.recovery={"retrying":game.recovery.retrying,"resumed":game.recovery.resumed,"reserved":game.recovery.reservations.size(),"occupied":game.occupied_slots() if game.is_host else game.players.size()}
	value.fixture_barrier=fixture_barrier.serial
	write_json("response.json",{"id":request.id,"result":value});busy=false

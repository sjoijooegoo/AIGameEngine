extends Node3D
## Only this node owns the wire protocol. No gameplay callbacks are exposed remotely.
const PROTOCOL := 5
const PlayerBody = preload("res://coop/player.gd")
const RpcCodec = preload("res://coop/rpc_codec.gd")
var players: Dictionary={}
var pending: Dictionary={}
var peer: ENetMultiplayerPeer
var is_host := false
var max_players := 4
var tick := 0
var latest_tick := -1
var sequence := 0
var roster_revision := 0
var local_id := 0
var status := "未连接"
var player_name := "玩家"
var held: Dictionary={}
var yaw := 0.0
var pitch := 0.0
var map_hash := ""
var camera: Camera3D
var panel: Control
var testing := false
var visual := true
var input_enabled := false
var connection_age := 0.0
var rejected_inputs := 0
var last_sent_axes := Vector2.INF
var last_sent_run := false
var ready_peers: Dictionary={}
var prediction_enabled := false
var prediction=preload("res://coop/movement_prediction.gd").new()
var input_history: Array=[]
var pending_reconcile: Dictionary={}
signal status_changed

func _ready() -> void:
	name="Coop"
	# Git's Windows line ending conversion must not break Linux interoperability.
	map_hash=FileAccess.get_file_as_string("res://coop/bank_layout.json").replace("\r\n","\n").sha256_text()
	multiplayer.allow_object_decoding=false
	multiplayer.server_relay=false
	multiplayer.auth_timeout=12.0
	multiplayer.auth_callback=_authenticate
	multiplayer.peer_authenticating.connect(_authenticating)
	multiplayer.peer_authentication_failed.connect(_authentication_failed)
	multiplayer.peer_connected.connect(_connected)
	multiplayer.peer_disconnected.connect(_disconnected)
	multiplayer.connection_failed.connect(func():connection_lost("无法连接服务器"))
	multiplayer.server_disconnected.connect(func():connection_lost("服务器已断开"))
	multiplayer.connected_to_server.connect(func():local_id=multiplayer.get_unique_id();set_status("正在进入银行…"))
	if visual:
		camera=Camera3D.new();camera.position=Vector3(22,1.62,16);camera.near=.05;camera.fov=75;camera.current=true;add_child(camera)
		var layer:=CanvasLayer.new();add_child(layer)
		panel=preload("res://coop/ui.gd").new();panel.game=self;layer.add_child(panel)
	var args:=OS.get_cmdline_user_args()
	var port:=24567;var address:="";var server:=OS.has_feature("dedicated_server")
	for arg in args:
		if arg=="--server":server=true
		elif arg.begins_with("--connect="):address=arg.trim_prefix("--connect=")
		elif arg.begins_with("--port="):port=arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--name="):player_name=arg.trim_prefix("--name=")
		elif arg.begins_with("--max-players="):max_players=arg.trim_prefix("--max-players=").to_int()
	if server:
		if start_server(port,max_players)!=OK:get_tree().quit(1)
	elif not address.is_empty():join_game(address,port,player_name)

func set_status(message: String) -> void:
	status=message;status_changed.emit();print("COOP_STATUS ",message)

func start_server(port: int, limit: int=4) -> Error:
	if port<1024 or port>65535 or limit<2 or limit>4:return ERR_INVALID_PARAMETER
	disconnect_game("")
	is_host=true;max_players=limit;peer=ENetMultiplayerPeer.new()
	# A few transport slots permit a bounded, explicit room-full handshake.
	# Pinned Godot 4.7.2 forwards max_channels+2 into incoming bandwidth.
	# create_server(..., 6) advertises only 8 BYTES/s and a 4 KiB window on
	# the wire. Use its unlimited default, then set the channel bound directly.
	var error:=peer.create_server(port,limit+4,0)
	if error!=OK:set_status("服务端端口不可用：%d" % port);peer=null;is_host=false;return error
	peer.host.channel_limit(8)
	multiplayer.multiplayer_peer=peer
	set_status("服务端监听 UDP %d，人数上限 %d" % [port,limit])
	return OK

func join_game(address: String, port: int, label: String) -> Error:
	if address.strip_edges().is_empty() or port<1024 or port>65535:return ERR_INVALID_PARAMETER
	if address.strip_edges().to_lower()=="localhost":address="127.0.0.1"
	disconnect_game("")
	player_name=label.strip_edges().substr(0,24)
	if player_name.is_empty():player_name="玩家"
	if panel:
		panel.address.text=address.strip_edges();panel.port.value=port;panel.nickname.text=player_name
	peer=ENetMultiplayerPeer.new()
	var error:=peer.create_client(address.strip_edges(),port,6)
	if error!=OK:set_status("创建连接失败");peer=null;return error
	multiplayer.multiplayer_peer=peer;connection_age=0
	set_status("正在连接 %s:%d…" % [address,port])
	return OK

func disconnect_game(message: String="已退出房间") -> void:
	input_enabled=false;held.clear()
	if peer:peer.close()
	multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new();peer=null
	for body in players.values():body.free()
	players.clear();pending.clear();local_id=0;is_host=false
	ready_peers.clear();input_history.clear();prediction.reset();pending_reconcile.clear()
	tick=0;latest_tick=-1;sequence=0;roster_revision=0;connection_age=0
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if not message.is_empty():set_status(message)

func connection_lost(message: String) -> void:
	disconnect_game(message)

func auth_request() -> Dictionary:return {}
func auth_response(_id: int) -> Dictionary:return {}
func accept_auth_response(_value: Dictionary) -> void:pass
func occupied_slots() -> int:return players.size()+pending.size()
func reserved_slots() -> Array:return []
func network_epoch() -> int:return 0
func client_can_move() -> bool:return input_enabled
func reliable_carrier() -> bool:return false
func connection_timeout() -> float:return 25.0
func reserve_peer(id: int,value: Dictionary) -> String:
	if occupied_slots()>=max_players:return "房间已满"
	pending[id]=value.name.strip_edges()
	return ""

func _authenticating(id: int) -> void:
	if not is_host and id==1:
		var request:={"protocol":PROTOCOL,"map":map_hash,"name":player_name};request.merge(auth_request())
		multiplayer.send_auth(1,JSON.stringify(request).to_utf8_buffer())

func _authenticate(id: int, bytes: PackedByteArray) -> void:
	if bytes.size()>512:return
	var value=JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary:return
	if is_host:
		if pending.has(id):return
		var reason:=""
		if value.get("protocol")!=PROTOCOL or value.get("map")!=map_hash:reason="客户端版本或地图不一致"
		elif not value.get("name") is String or value.name.length()>24 or value.name.strip_edges().is_empty():reason="玩家名称无效"
		else:reason=reserve_peer(id,value)
		var reply:={"accepted":reason.is_empty(),"reason":reason,"protocol":PROTOCOL,"map":map_hash,"limit":max_players}
		if reason.is_empty():reply.merge(auth_response(id))
		multiplayer.send_auth(id,JSON.stringify(reply).to_utf8_buffer())
		if reason.is_empty():
			multiplayer.complete_auth(id)
	else:
		if id!=1:return
		if value.get("accepted")!=true:
			disconnect_game.call_deferred(str(value.get("reason","连接被拒绝")));return
		if value.get("protocol")!=PROTOCOL or value.get("map")!=map_hash:
			disconnect_game.call_deferred("服务器版本或地图不一致");return
		max_players=clampi(int(value.get("limit",4)),2,4)
		accept_auth_response(value)
		multiplayer.complete_auth(1)

func _authentication_failed(id: int) -> void:
	pending.erase(id)
	if not is_host and peer:connection_lost.call_deferred("握手超时，连接中断")

func _connected(id: int) -> void:
	if not is_host:return
	if not pending.has(id):multiplayer.disconnect_peer(id);return
	var occupied: Array=reserved_slots()
	for body in players.values():occupied.append(body.slot)
	var slot:=0
	while slot in occupied:slot+=1
	var body=PlayerBody.new();add_child(body);body.configure(id,slot,pending[id],false)
	body.position=Vector3(21.0+float(slot)*1.0,.05,16.0);body.rotation.y=PI
	players[id]=body;pending.erase(id)
	prepare_player(body)
	broadcast_roster()
	print("COOP_JOIN ",id," slot=",slot," players=",players.size())

func prepare_player(_body: CharacterBody3D) -> void:
	pass

func _disconnected(id: int) -> void:
	pending.erase(id)
	ready_peers.erase(id)
	if not is_host:return
	if players.has(id):players[id].free();players.erase(id)
	broadcast_roster()
	print("COOP_LEAVE ",id," players=",players.size())

func all_states() -> Array:
	var states: Array=[]
	for id in players:states.append(players[id].snapshot())
	return states

func broadcast_roster() -> void:
	roster_revision+=1
	# ENet can dispatch several disconnects in one poll. The multiplayer roster
	# may still contain another peer whose native channel array is already gone.
	var rows:=all_states()
	for id in players:
		if connected_peer(id):_receive_roster.rpc_id(id,roster_revision,rows,network_epoch(),tick)

func connected_peer(id: int) -> bool:
	return peer!=null and multiplayer.get_peers().has(id) and peer.get_peer(id).get_state()==ENetPacketPeer.STATE_CONNECTED

func ready_ids() -> Array:
	var ids: Array=[]
	for id in players:
		if ready_peers.get(id,-1)==roster_revision and connected_peer(id):ids.append(id)
	return ids

@rpc("any_peer","call_remote","reliable",0)
func _roster_ready(revision: int) -> void:
	var id:=multiplayer.get_remote_sender_id()
	if is_host and players.has(id) and revision==roster_revision:ready_peers[id]=revision

# Channel zero is ordered behind the engine's own authentication completion.
# No other channels are sent until this roster is acknowledged by the client.
@rpc("authority","call_remote","reliable",0)
func _receive_roster(revision: int, rows: Array,_epoch: int=0,_server_tick: int=0) -> void:
	if is_host or revision<roster_revision:return
	roster_revision=revision
	var present: Array=[]
	for row in rows:
		var id: int=row.id;present.append(id)
		if not players.has(id):
			var body=PlayerBody.new();add_child(body);body.configure(id,row.slot,row.name,visual)
			players[id]=body;body.apply_snapshot(row,true)
			if id==local_id:
				yaw=row.yaw;pitch=row.pitch;input_enabled=true
				if not testing:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for id in players.keys():
		if id not in present:players[id].free();players.erase(id)
	_roster_ready.rpc_id(1,revision)
	set_status("已连接 · %d/%d 人" % [players.size(),max_players])

@rpc("any_peer","call_remote","unreliable_ordered",0)
func _submit_input(serial: int, move: Vector2, look_yaw: float, look_pitch: float, sprint: bool) -> void:
	accept_input(multiplayer.get_remote_sender_id(),serial,move,look_yaw,look_pitch,sprint)

@rpc("any_peer","call_remote","reliable",0)
func _confirm_input(serial: int, move: Vector2, look_yaw: float, look_pitch: float, sprint: bool) -> void:
	accept_input(multiplayer.get_remote_sender_id(),serial,move,look_yaw,look_pitch,sprint)

func accept_input(id: int, serial: int, move: Vector2, look_yaw: float, look_pitch: float, sprint: bool) -> void:
	if not is_host:return
	if not players.has(id):return
	var body=players[id]
	if serial<=body.last_sequence or serial>2147483647 or not move.is_finite() or not is_finite(look_yaw) or not is_finite(look_pitch):
		rejected_inputs+=1;return
	body.last_sequence=serial;body.axes=move.limit_length(1.0)
	body.rotation.y=wrapf(look_yaw,-PI,PI);body.aim_pitch=clampf(look_pitch,-1.25,1.25)
	body.running=sprint;body.last_input_tick=tick

@rpc("any_peer","call_remote","unreliable",4)
func _input_bundle(epoch: int,wire: PackedByteArray) -> void:
	var id:=multiplayer.get_remote_sender_id()
	if not is_host or not players.has(id) or epoch!=network_epoch():return
	var body=players[id]
	if body.input_budget<1:return
	body.input_budget-=1
	var rows:=RpcCodec.decode(wire)
	if rows.size()>12:return
	for row in rows:
		if not row is Array or row.size()!=6:return
		if not row[0] is int or not row[1] is Vector2 or not (row[2] is float) or not (row[3] is float) or not row[4] is bool or not row[5] is int:return
		if not row[1].is_finite() or not is_finite(row[2]) or not is_finite(row[3]):rejected_inputs+=1;continue
		var serial: int=row[0]
		if serial<=body.last_sequence or serial>2147483647 or tick-row[5]>180 or row[5]>tick+6:continue
		if body.commands.size()<120:body.commands[serial]=row

@rpc("any_peer","call_remote","reliable",2)
func _input_checkpoint(epoch: int,wire: PackedByteArray) -> void:
	_input_bundle(epoch,wire)

func consume_input(body) -> void:
	body.axes=Vector2.ZERO;body.running=false
	if body.commands.is_empty():return
	var serial: int=body.commands.keys().min()
	var row: Array=body.commands[serial];body.commands.erase(serial)
	if serial<=body.last_sequence or tick-row[5]>180:return
	body.last_sequence=serial;body.axes=Vector2(row[1]).limit_length(1.0)
	body.rotation.y=wrapf(row[2],-PI,PI);body.aim_pitch=clampf(row[3],-1.25,1.25)
	body.running=row[4];body.last_input_tick=tick

@rpc("authority","call_remote","unreliable_ordered",1)
func _receive_snapshot(server_tick: int, revision: int, wire: PackedByteArray,epoch: int=0) -> void:
	if is_host or server_tick<=latest_tick or revision!=roster_revision or epoch!=network_epoch():return
	var rows:=RpcCodec.decode(wire)
	if rows.is_empty() or rows.size()>4:return
	latest_tick=server_tick
	for row in rows:
		if players.has(int(row.id)):
			if prediction_enabled and int(row.id)==local_id:pending_reconcile=row
			else:players[int(row.id)].apply_snapshot(row)

func _physics_process(dt: float) -> void:
	if not testing:advance(dt)

func advance(dt: float) -> void:
	if peer==null:return
	if is_host:
		tick+=1
		for body in players.values():body.simulate(dt,tick)
		if tick%3==0:
			broadcast_players()
	else:
		connection_age+=dt
		if not players.has(local_id):
			if connection_age>connection_timeout():connection_lost("连接超时")
			return
		var move:=Vector2(float(held.get(KEY_D,false))-float(held.get(KEY_A,false)),float(held.get(KEY_S,false))-float(held.get(KEY_W,false))) if input_enabled else Vector2.ZERO
		sequence+=1
		var sprint: bool=input_enabled and held.get(KEY_SHIFT,false)
		if prediction_enabled:
			if not pending_reconcile.is_empty():prediction.reconcile(players[local_id],pending_reconcile);pending_reconcile={}
			if not client_can_move():move=Vector2.ZERO;sprint=false
			input_history.append([sequence,move.limit_length(1.0),yaw,pitch,sprint,maxi(latest_tick,0)])
			while input_history.size()>12:input_history.pop_front()
			# 30 Hz plus edges; repeated recent commands recover loss without a
			# reliable head-of-line queue. Server consumes at most one per tick.
			var send_bundle: bool=sequence%2==0 or move!=last_sent_axes or sprint!=last_sent_run
			var send_checkpoint: bool=sequence%6==1 and not reliable_carrier()
			var wire:=RpcCodec.encode(input_history) if send_bundle or send_checkpoint else PackedByteArray()
			if send_bundle:_input_bundle.rpc_id(1,network_epoch(),wire)
			# Bounded 10 Hz recovery on an independent channel; unreliable updates
			# remain current even if reliable delivery stalls. Server age/credit
			# limits prevent replaying a backlog as extra movement after an outage.
			if send_checkpoint:_input_checkpoint.rpc_id(1,network_epoch(),wire)
			prediction.advance(players[local_id],sequence,move,yaw,sprint,dt,client_can_move())
		elif move!=last_sent_axes or sprint!=last_sent_run or sequence%12==1:_confirm_input.rpc_id(1,sequence,move.limit_length(1.0),yaw,pitch,sprint)
		else:_submit_input.rpc_id(1,sequence,move.limit_length(1.0),yaw,pitch,sprint)
		last_sent_axes=move;last_sent_run=sprint
		for body in players.values():body.present(dt,body.peer_id==local_id,prediction_enabled and body.peer_id==local_id)
		if camera:
			camera.position=players[local_id].position+Vector3.UP*1.62
			camera.rotation=Vector3(pitch,yaw,0)

func broadcast_players() -> void:
	var wire:=RpcCodec.encode(all_states())
	for id in ready_ids():_receive_snapshot.rpc_id(id,tick,roster_revision,wire,network_epoch())

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT] and (input_enabled or not event.pressed):held[key]=event.pressed
		if key==KEY_ESCAPE and event.pressed and not event.echo and players.has(local_id):
			input_enabled=not input_enabled;held.clear()
			Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if input_enabled else Input.MOUSE_MODE_VISIBLE
			status_changed.emit()
	if event is InputEventMouseMotion and input_enabled:
		yaw=wrapf(yaw-event.relative.x*.0025,-PI,PI);pitch=clampf(pitch-event.relative.y*.0025,-1.25,1.25)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and not testing:
		held.clear();input_enabled=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		status_changed.emit()

func observe() -> Dictionary:
	var rows: Array=[]
	for body in players.values():rows.append(body.observe())
	var network: Dictionary={}
	if peer:
		for id in multiplayer.get_peers():
			var connection:=peer.get_peer(id)
			network[id]={"rtt_ms":connection.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),"throttle":connection.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)}
	return {"status":status,"server":is_host,"local_id":local_id,"tick":tick,"input_sequence":sequence,"snapshot_tick":latest_tick,"revision":roster_revision,"players":rows,"rejected_inputs":rejected_inputs,"network":network}

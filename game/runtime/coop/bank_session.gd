extends "res://coop/session.gd"
## Current bank integration. Only the server advances combat, navigation and doors.
var world: Node3D
var active := false
var contexts: Dictionary={}
var original_player: CharacterBody3D
var original_weapon: Node
var original_feedback: RefCounted
var local_server_pid := -1
var owner_pid := -1
var launch_port := 24567
var preferred_address := "127.0.0.1"
var launch_age := 0.0
var launching := false
var action_sequence := 0
var bank_tick := -1
var round_id := 1
var received_round := 0
var replicas: Dictionary={}
var team: Dictionary={}
var team_wiped := false
var received_shots := -1
var clock_age := 0.0
var wire_bytes := 0
var server_tick_usec := 0
var server_peak_usec := 0
var snapshot_buffer=preload("res://coop/snapshot_buffer.gd").new()
var recovery=preload("res://coop/session_recovery.gd").new()
var network_stalled := false
var leaving := false
var leave_deadline := 0
var preview_fire: Dictionary={}
var preview_cooldown := 0.0
var preview_count := 0
var local_fire_age := 99.0
var local_fire_weapon := ""
var local_fire_base := -1
var local_fire_duration := 1.0
var reserved_count := 0
var pending_actions: Array=[]
var ready_written := false
var last_bank_received_msec := 0
var lease_written_msec := -1000
var started := false
var leader := 0
var equipment: Dictionary={}
var remote_shots: Dictionary={}
var closing := false
var frontend_managed := false
var discovery: Node
var client_resources: Array=[]
var client_prepared := false
var presentation=preload("res://coop/world_presentation.gd").new()

func _ready() -> void:
	recovery.game=self;prediction_enabled=true
	presentation.world=world
	original_player=world.player;original_weapon=world.firearms;original_feedback=world.feedback
	frontend_managed=AppFlow.intent.get("mode")=="multiplayer"
	if frontend_managed:active=true
	testing=world.testing;visual=false
	for arg in OS.get_cmdline_user_args():
		if arg=="--server":active=true
		if arg.begins_with("--connect=") or arg=="--coop":active=true
		if arg.begins_with("--connect="):preferred_address=arg.trim_prefix("--connect=")
		if arg.begins_with("--port="):launch_port=arg.trim_prefix("--port=").to_int()
		if arg.begins_with("--owner-pid="):owner_pid=arg.trim_prefix("--owner-pid=").to_int()
	super._ready()
	visual=not is_host
	# Protocol includes the real bank rules and layout, not the old structural slice.
	var fingerprint:="bank-combat-v4"
	for path in ["origin_structure","infected","infected_archetypes","firearms","door_design","shooting_feedback"]:
		fingerprint+=FileAccess.get_file_as_string("res://data/"+path+".json").replace("\r\n","\n")
	map_hash=fingerprint.sha256_text()
	if not is_host:
		var layer:=CanvasLayer.new();layer.layer=30;add_child(layer)
		panel=preload("res://coop/bank_ui.gd").new();panel.game=self;layer.add_child(panel)
		panel.nickname.text=player_name;panel.address.text=preferred_address;panel.port.value=launch_port
		panel.capacity.select(max_players-2)
	if active:open_menu()
	set_process_input(false) # Bank's normal input handler owns focus/UI routing.

func _physics_process(_dt: float) -> void:
	pass # advanced by the bank's fixed tick / debug adapter, never twice

func _process(_dt: float) -> void:
	recovery.advance()
	if leaving and Time.get_ticks_msec()>=leave_deadline:finish_leave()
	# OS.is_process_running only reliably tracks this process's own children.
	# An owned server watches a local lease instead of trying to query its parent.
	if local_server_pid>0 and Time.get_ticks_msec()-lease_written_msec>1000:
		write_lease()

func write_lease() -> void:
	var file:=FileAccess.open("user://coop_owner_"+str(OS.get_process_id())+".json",FileAccess.WRITE)
	if file:file.store_string(str(Time.get_unix_time_from_system()));file.close()
	lease_written_msec=Time.get_ticks_msec()

func open_menu() -> void:
	active=true;input_enabled=false;held.clear();world.held_actions.clear()
	world.firearms.clear_input();world.ui.set_mode("play")
	send_action("trigger",false)
	preload("res://coop/input_capture.gd").release(get_viewport())
	if panel:panel.refresh()

func resume() -> void:
	if not players.has(local_id) or not started or recovery.retrying or leaving:return
	input_enabled=true;world.ui.set_mode("play");Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	panel.refresh()

func restore_local() -> void:
	world.player=original_player;world.firearms=original_weapon;world.feedback=original_feedback

func disconnect_game(message: String="已退出会话") -> void:
	if is_host:recovery.clear_server()
	if not message.is_empty():recovery.cancel()
	for context in contexts.values():context.weapon.queue_free()
	contexts.clear();restore_local()
	super.disconnect_game(message)
	equipment.clear();remote_shots.clear();snapshot_buffer.reset()
	preview_fire.clear();preview_cooldown=0;network_stalled=false
	local_fire_age=99;local_fire_weapon=""
	reserved_count=0
	pending_actions.clear()
	team.clear();replicas.clear();presentation.reset();bank_tick=-1;received_round=0;received_shots=-1;team_wiped=false
	started=false;leader=0;last_bank_received_msec=0
	world.player.collision_layer=2;world.player.collision_mask=9
	if panel:panel.refresh()
	if frontend_managed and not closing and not message.is_empty():AppFlow.return_menu("multiplayer",message)

func leave_session() -> void:
	if recovery.retrying:recovery.cancel()
	if peer and players.has(local_id):
		leaving=true;leave_deadline=Time.get_ticks_msec()+2000;open_menu()
		_leave_intent.rpc_id(1);set_status("正在离开会话…");return
	finish_leave()

@rpc("any_peer","call_remote","reliable",0)
func _leave_intent() -> void:
	var id:=multiplayer.get_remote_sender_id()
	if is_host and players.has(id):
		recovery.voluntary[id]=true
		_leave_accepted.rpc_id(id)

@rpc("authority","call_remote","reliable",0)
func _leave_accepted() -> void:
	if leaving:finish_leave.call_deferred()

func finish_leave() -> void:
	leaving=false;recovery.cancel()
	if frontend_managed:AppFlow.return_menu("multiplayer");return
	disconnect_game();launching=false
	if local_server_pid>0 and OS.is_process_running(local_server_pid):OS.kill(local_server_pid)
	local_server_pid=-1;world.reset_fixture("default");open_menu()

func back_to_solo() -> void:
	if frontend_managed:AppFlow.return_menu("multiplayer");return
	leave_session();active=false;panel.refresh();world.ui.set_mode("pause")

func shutdown() -> void:
	recovery.cancel()
	closing=true;launching=false;disconnect_game("")
	stop_owned_server()

func stop_owned_server() -> void:
	if local_server_pid>0 and OS.is_process_running(local_server_pid):OS.kill(local_server_pid)
	local_server_pid=-1

func _exit_tree() -> void:
	stop_owned_server()
	if peer:peer.close()

func create_session(port_number: int, limit: int, label: String) -> void:
	if launching or peer!=null:return
	launch_port=port_number;player_name=label;max_players=clampi(limit,2,4)
	var args:=PackedStringArray(["--headless","--log-file",ProjectSettings.globalize_path("user://coop-server-"+str(OS.get_process_id())+".log")])
	if OS.has_feature("editor"):args.append_array(["--path",ProjectSettings.globalize_path("res://")])
	args.append_array(["--","--server","--port="+str(port_number),"--max-players="+str(max_players),"--owner-pid="+str(OS.get_process_id())])
	var ready_path:="user://coop_ready_"+str(OS.get_process_id())+".json"
	if FileAccess.file_exists(ready_path):DirAccess.remove_absolute(ready_path)
	write_lease()
	local_server_pid=OS.create_process(OS.get_executable_path(),args,false)
	if local_server_pid<=0:disconnect_game("本地服务端启动失败");return
	launch_age=0;launching=true;set_status("正在加载本地银行服务端…")

func join_game(address: String, port_number: int, label: String) -> Error:
	if not recovery.retrying:recovery.token=""
	recovery.endpoint={"address":address,"port":port_number,"label":label}
	active=true;world.ui.set_mode("play");world.ensure_infected()
	prepare_client_resources()
	var result:=super.join_game(address,port_number,label)
	world.player.collision_layer=0;world.player.collision_mask=0
	for enemy in world.infected:enemy.visible=false;enemy.collision_layer=0;enemy.head_hitbox.collision_layer=0
	return result

func prepare_client_resources() -> void:
	if client_prepared:return
	# Keep imported scenes and the immutable upper-body library resident BEFORE
	# ENet's RTT handshake. First-roster loading must not throttle live snapshots.
	for path in ["res://coop/local_reference/manifest.json","res://coop/local_reference/weapons.json"]:
		if not FileAccess.file_exists(path):continue
		var data=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:continue
		var entries: Array=[data] if data.has("resource") else data.get("weapons",{}).values()
		for entry in entries:
			var resource:=str(entry.get("resource",""))
			if resource.begins_with("res://coop/local_reference/") and ResourceLoader.exists(resource):client_resources.append(load(resource))
	var warmup=preload("res://coop/avatar.gd").new();warmup.visible=false;add_child(warmup)
	warmup.setup(0);warmup.free();client_prepared=true

func start_server(port_number: int, limit: int=4) -> Error:
	# Finish expensive actor setup before accepting ENet handshakes. Otherwise
	# the first client's RTT spike can throttle all its unreliable traffic.
	world.ensure_infected()
	var error:=super.start_server(port_number,limit)
	if error==OK:
		discovery=preload("res://coop/discovery.gd").new();add_child(discovery)
		if discovery.serve(self,port_number)!=OK:push_warning("Server discovery port unavailable; direct joining is still available")
	return error

func prepare_player(body: CharacterBody3D) -> void:
	world.ensure_infected()
	if contexts.is_empty() and recovery.reservations.is_empty() and tick>0:
		restore_local();world.reset_fixture("default");round_id+=1
	body.position=Vector3(23.0-float(body.slot)*.7,.05,8.2);body.rotation.y=-1.120596
	var context=preload("res://coop/bank_peer.gd").new();context.setup(world,body);contexts[body.peer_id]=context
	started=true # A successful authenticated join starts/resumes this world immediately.
	if leader==0:leader=body.peer_id
	original_player.collision_layer=0

func _connected(id: int) -> void:
	if peer:peer.get_peer(id).set_timeout(32,4000,12000)
	if is_host and recovery.tokens.has(id):
		var old_id: int=recovery.active_id(recovery.tokens[id])
		if old_id>0 and old_id!=id:
			multiplayer.disconnect_peer(old_id);_disconnected(old_id)
		var restored=recovery.take(id)
		if restored!=null:
			contexts[id]=restored;players[id]=restored.body;pending.erase(id)
			started=true
			if leader==0:leader=id
			broadcast_roster();return
	super._connected(id)

func occupied_slots() -> int:return recovery.count()
func reserved_slots() -> Array:return recovery.slots()
func network_epoch() -> int:return round_id if is_host else received_round
func auth_request() -> Dictionary:return {"resume":recovery.token}
func reserve_peer(id: int,value: Dictionary) -> String:return recovery.reserve(id,value)
func auth_response(id: int) -> Dictionary:return {"resume":recovery.tokens.get(id,"")}
func connection_timeout() -> float:return 12.0 if recovery.retrying else 25.0
func accept_auth_response(value: Dictionary) -> void:recovery.token=str(value.get("resume",""))
func client_can_move() -> bool:
	var state: Dictionary=team.get(local_id,{})
	return input_enabled and started and not network_stalled and not recovery.retrying and not state.get("dead",false) and not state.get("grabbed",false)

func network_summary() -> String:
	if recovery.retrying:return "连接中断 · 正在自动重连"
	if network_stalled:return "连接不稳定 · 暂停操作，等待恢复"
	if peer and multiplayer.get_peers().has(1):
		var ping:=int(peer.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		var age:=Time.get_ticks_msec()-last_bank_received_msec if last_bank_received_msec>0 else 0
		return "延迟 %d ms%s" % [ping," · 网络波动" if ping>300 or age>350 else ""]
	return "正在同步…"

func connection_lost(message: String) -> void:
	if closing or leaving:finish_leave();return
	if not recovery.lost(message):disconnect_game(message)

func _authentication_failed(id: int) -> void:
	if is_host:recovery.tokens.erase(id)
	super._authentication_failed(id)

func _roster_ready(revision: int) -> void:
	super._roster_ready(revision)
	var id:=multiplayer.get_remote_sender_id()
	# A round can restart while the roster acknowledgement is in flight.
	# Confirm the current epoch on the ordered control channel before snapshots.
	if is_host and ready_peers.get(id,-1)==roster_revision:
		_round_reset.rpc_id(id,round_id,tick,all_states())

func _disconnected(id: int) -> void:
	if contexts.has(id):
		var context=contexts[id];context.bind(world)
		if context.feedback.is_grabbed():context.feedback.release("disconnected")
		if not recovery.keep(id,context):context.weapon.queue_free()
		contexts.erase(id);restore_local()
		if leader==id:leader=int(contexts.keys()[0]) if not contexts.is_empty() else 0
		if contexts.is_empty():started=false
	else:recovery.tokens.erase(id)
	super._disconnected(id)

func _receive_roster(revision: int, rows: Array,epoch: int=0,server_tick: int=0) -> void:
	super._receive_roster(revision,rows,epoch,server_tick)
	if epoch>received_round:_round_reset(epoch,server_tick,rows)
	for id in equipment.keys():
		if not players.has(id):equipment.erase(id)
	for id in players:
		if id!=local_id and not equipment.has(id):
			var visual=preload("res://coop/equipment.gd").new();players[id].add_child(visual);visual.setup(players[id]);equipment[id]=visual
	if players.has(local_id):
		players[local_id].collision_mask=9
		original_player.position=players[local_id].position;original_player.rotation.y=yaw
		world.camera_motion.reset();world.ui.set_mode("play")
		if not started:open_menu()
		if panel:panel.refresh()

func _input(_event: InputEvent) -> void:
	pass

func handle_event(event: InputEvent) -> void:
	if is_host:return
	if event is InputEventKey:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_ESCAPE and event.pressed and not event.echo:
			if input_enabled:open_menu()
			else:resume()
			get_viewport().set_input_as_handled()
			return
		if key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT] and (input_enabled or not event.pressed):held[key]=event.pressed
		if input_enabled and event.pressed and not event.echo:
			if key in [KEY_1,KEY_2,KEY_3,KEY_4]:send_action("weapon",{KEY_1:"pistol",KEY_2:"shotgun",KEY_3:"torch",KEY_4:"baton"}[key])
			if key==KEY_R:send_action("reload",true)
			if key==KEY_E:send_action("door",true)
			if key in [KEY_A,KEY_D]:send_action("struggle",key)
			if key==KEY_F:world.flashlight.visible=not world.flashlight.visible
	if event is InputEventMouseMotion and input_enabled:
		yaw=wrapf(yaw-event.relative.x*.0025*float(world.ui.settings.sensitivity),-PI,PI)
		pitch=clampf(pitch-event.relative.y*.0025*float(world.ui.settings.sensitivity),-1.25,1.25)
		world.firearms.view.mouse_motion(event.relative)
	if event is InputEventMouseButton and input_enabled:
		if event.button_index==MOUSE_BUTTON_LEFT:send_action("trigger",event.pressed)
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:send_action("shove",true)

func send_action(kind: String, value: Variant) -> void:
	if peer==null or not players.has(local_id):return
	if network_stalled and not (kind=="trigger" and value==false):return
	action_sequence+=1
	_action.rpc_id(1,action_sequence,kind,value,yaw,pitch,received_round,latest_tick)
	pending_actions.append([action_sequence,kind,value,yaw,pitch,received_round,latest_tick])
	while pending_actions.size()>8:pending_actions.pop_front()
	_action_bundle.rpc_id(1,pending_actions)
	if kind=="trigger" and value==true:preview_shot(action_sequence)

@rpc("any_peer","call_remote","unreliable_ordered",5)
func _action_bundle(rows: Array) -> void:
	if not is_host or rows.size()>8:return
	var previous := -1
	for row in rows:
		if not row is Array or row.size()!=7 or not row[0] is int or not row[1] is String or not row[3] is float or not row[4] is float or not row[5] is int or not row[6] is int:return
		if int(row[0])<=previous:return
		previous=row[0]
	for row in rows:_action(row[0],row[1],row[2],row[3],row[4],row[5],row[6])

func preview_shot(serial: int) -> void:
	var weapon=world.firearms;var state: Dictionary=team.get(local_id,{})
	if not client_can_move() or preview_cooldown>0 or weapon.selected not in ["pistol","shotgun"] or not weapon.phase in ["idle","fire","fire_last"]:return
	if int(state.get("ammo",{}).get(weapon.selected,{}).get("clip",0))<=preview_fire.size():return
	preview_cooldown=float(weapon.data.weapons[weapon.selected].cycle)
	preview_fire[serial]=Time.get_ticks_msec();preview_count+=1
	local_fire_age=0;local_fire_weapon=weapon.selected;local_fire_base=int(state.get("shots",0))
	local_fire_duration=float(weapon.data.pins.pistol.clips.fire) if weapon.selected=="pistol" else float(weapon.data.weapons.shotgun.cycle)
	weapon.flash_time=.05;weapon.play_sound(weapon.selected);weapon.recoil.x=.035

@rpc("any_peer","call_remote","reliable",3)
func _action(serial: int, kind: String, value: Variant, aim_yaw: float, aim_pitch: float,epoch: int,seen_tick: int) -> void:
	var id:=multiplayer.get_remote_sender_id()
	if not is_host or not contexts.has(id):return
	var context=contexts[id]
	if epoch!=round_id or seen_tick>tick+6 or tick-seen_tick>180:return
	if serial<=context.last_action or not is_finite(aim_yaw) or not is_finite(aim_pitch) or context.action_budget<1 or context.actions.size()>=40:return
	if kind not in ["trigger","shove","weapon","reload","door","struggle","restart"]:return
	if kind=="weapon" and value not in ["pistol","shotgun","torch","baton"]:return
	if kind=="struggle" and value not in [KEY_A,KEY_D]:return
	if kind in ["trigger","shove","reload","door","restart"] and not value is bool:return
	context.last_action=serial;context.action_budget-=1
	context.actions.append([kind,value,wrapf(aim_yaw,-PI,PI),clampf(aim_pitch,-1.25,1.25),seen_tick])

func apply_action(context, action: Array) -> void:
	context.body.rotation.y=action[2];context.body.aim_pitch=action[3];world.pitch=action[3];world.update_camera()
	if action[0]=="restart":return
	if world.player_dead:return
	match action[0]:
		"weapon":world.firearms.select_weapon(action[1])
		"reload":world.firearms.reload()
		"trigger":
			if world.firearms.selected!="torch":world.firearms.press_trigger(action[1])
			elif action[1] and world.firearms.shove():world.strike_kind="hit";world.strike_time=0;world.strike_applied=false;world.strike_cooldown=.52
		"shove":
			if world.firearms.shove():world.strike_kind="push";world.strike_time=0;world.strike_applied=false;world.strike_cooldown=.52
		"struggle":world.feedback.struggle(action[1])
		"door":
			var door: String=world.aimed_door()
			if not door.is_empty():world.doors[door].toggle(world.player.global_position)

func advance(dt: float) -> void:
	if not active:return
	clock_age+=dt
	preview_cooldown=maxf(0,preview_cooldown-dt)
	local_fire_age+=dt
	if not is_host and players.has(local_id) and last_bank_received_msec>0:
		var stalled: bool=Time.get_ticks_msec()-last_bank_received_msec>1500
		if stalled and not network_stalled:
			held.clear();world.firearms.clear_input();prediction.reset();input_history.clear()
		network_stalled=stalled
	if not is_host and players.has(local_id) and last_bank_received_msec>0 and Time.get_ticks_msec()-last_bank_received_msec>8000:
		connection_lost("服务器响应超时，连接已断开");return
	if launching:
		launch_age+=dt
		if not OS.is_process_running(local_server_pid):launching=false;disconnect_game("服务端未能启动，请检查端口是否占用");return
		elif FileAccess.file_exists("user://coop_ready_"+str(OS.get_process_id())+".json"):
			launching=false;join_game("127.0.0.1",launch_port,player_name)
		elif launch_age>90:launching=false;disconnect_game("本地服务端加载超时");return
	if is_host:
		if owner_pid>0 and Time.get_unix_time_from_system()-FileAccess.get_modified_time("user://coop_owner_"+str(owner_pid)+".json")>15:
			get_tree().quit();return
		server_advance(dt);return
	var profile_stage: int=world.profiler.mark()
	super.advance(dt)
	world.profiler.end_scope("client_prediction_players",profile_stage)
	if not players.has(local_id):return
	var action_ack: int=team.get(local_id,{}).get("action_ack",0)
	while not pending_actions.is_empty() and (int(pending_actions[0][0])<=action_ack or latest_tick-int(pending_actions[0][6])>120):pending_actions.pop_front()
	if sequence%3==0 and not pending_actions.is_empty():_action_bundle.rpc_id(1,pending_actions)
	profile_stage=world.profiler.mark()
	for id in equipment:equipment[id].advance(dt,players[id].aim_pitch)
	world.profiler.end_scope("client_teammate_animation",profile_stage);profile_stage=world.profiler.mark()
	restore_local()
	var body=players[local_id]
	world.camera_motion.begin_tick();world.tick_count+=1
	world.player.position=body.position+prediction.correction;world.player.rotation.y=yaw;world.player.velocity=body.velocity;world.pitch=pitch
	world.feedback.advance(dt,body.motion!="idle")
	world.update_camera()
	world.firearms.audio.advance(dt);world.firearms.blood_fx.advance(dt)
	world.firearms.phase_time+=dt
	if world.firearms.phase in ["reload","reload_empty"] and world.firearms.selected=="pistol":
		world.firearms.timed_sound("mag_out",world.firearms.duration*.23);world.firearms.timed_sound("mag_in",world.firearms.duration*.68)
		if world.firearms.phase=="reload_empty":world.firearms.timed_sound("slide",world.firearms.duration*.89)
	if world.firearms.phase=="insert_shell":world.firearms.timed_sound("shell",world.firearms.duration*.75)
	if world.firearms.phase=="fire" and world.firearms.selected=="shotgun":world.firearms.timed_sound("pump",world.firearms.duration*.46,true)
	world.firearms.flash_time=maxf(0,world.firearms.flash_time-dt)
	world.firearms.hit_time=maxf(0,world.firearms.hit_time-dt)
	world.firearms.recoil=world.firearms.recoil.lerp(Vector2.ZERO,1-exp(-dt*12))
	var saved_phase: String=world.firearms.phase;var saved_time: float=world.firearms.phase_time;var saved_duration: float=world.firearms.duration
	if local_fire_weapon==world.firearms.selected and local_fire_age<local_fire_duration and saved_phase in ["idle","fire","fire_last"]:
		world.firearms.phase="fire";world.firearms.phase_time=local_fire_age;world.firearms.duration=local_fire_duration
	world.firearms.update_view(body.motion!="idle",world.sample_weapon_wall_distance(),dt)
	world.firearms.phase=saved_phase;world.firearms.phase_time=saved_time;world.firearms.duration=saved_duration
	if world.firearms.selected=="torch":world.held_weapon.advance(world.tick_count,body.motion!="idle",world.sample_weapon_wall_distance())
	world.profiler.end_scope("client_weapon_camera",profile_stage);profile_stage=world.profiler.mark()
	presentation.advance(dt)
	world.profiler.end_scope("client_world_presentation",profile_stage);profile_stage=world.profiler.mark()
	world.infected_audio.advance(dt);world.update_combat_ui()
	world.ui.hud.advance(dt);world.flashlight_lighting.advance(dt);world.door_lighting.advance();world.viewmodel_lighting.advance(dt)
	world.camera_motion.commit_tick()
	if panel:panel.refresh_hud()
	world.profiler.end_scope("client_hud_lighting_audio",profile_stage)

func server_advance(dt: float) -> void:
	world.ensure_infected()
	if not ready_written and owner_pid>0:
		var file:=FileAccess.open("user://coop_ready_"+str(owner_pid)+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"pid":OS.get_process_id()}));file.close();ready_written=true
	if contexts.is_empty():return
	var tick_started_usec:=Time.get_ticks_usec()
	var profile_stage: int=world.profiler.mark()
	tick+=1;world.tick_count=tick;world.navigation.begin_frame()
	var restart_requested:=false
	var grabbed_hits: Dictionary={}
	for id in contexts:
		if contexts[id].feedback.is_grabbed():grabbed_hits[id]=contexts[id].feedback.grabber.hit_count
	for id in contexts:
		var context=contexts[id]
		advance_player_commands(context,dt)
		context.bind(world);context.action_budget=minf(40,context.action_budget+dt*25)
		world.hurt_cooldown=maxf(0,world.hurt_cooldown-dt);world.strike_cooldown=maxf(0,world.strike_cooldown-dt)
		world.feedback.advance(dt,context.body.axes.length()>.1)
		var fresh_trigger := false
		for action in context.actions:
			if tick-int(action[4])>180:continue
			if action[0]=="restart":restart_requested=true
			else:
				apply_action(context,action)
				if action[0]=="trigger" and action[1]==true:fresh_trigger=true
		context.actions.clear()
		if world.player_dead or world.feedback.is_grabbed():context.body.axes=Vector2.ZERO
		if tick-context.body.last_input_tick>18:
			# A fresh, validated click may still fire once while movement packets
			# are delayed. Never keep the held trigger alive without input updates.
			if fresh_trigger:world.firearms.trigger=false
			else:world.firearms.clear_input()
		world.update_camera()
		if world.strike_time>=0:
			world.strike_time+=dt
			if world.strike_time>=.17 and not world.strike_applied:world.strike_applied=true;world.apply_player_strike()
			if world.strike_time>.42:world.strike_time=-1
		world.firearms.advance(dt,context.body.axes.length()>.1,10.0)
		context.save(world)
	for id in grabbed_hits:
		var context=contexts[id]
		if context.feedback.is_grabbed() and context.feedback.grabber.hit_count>int(grabbed_hits[id]):
			context.bind(world);context.feedback.release("teammate",true);context.save(world)
	world.profiler.end_scope("server_players_combat",profile_stage);profile_stage=world.profiler.mark()
	for door in world.doors.values():door.advance(dt)
	world.navigation.update_doors();world.crowd.rebuild(world.infected)
	world.profiler.end_scope("server_doors_crowd",profile_stage);profile_stage=world.profiler.mark()
	for enemy in world.infected:
		var target=choose_target(enemy)
		if target==null:continue
		target.bind(world);enemy.advance(dt);target.save(world)
		if enemy.active and enemy.mode!="dead":world.crowd.update(enemy)
	world.profiler.end_scope("server_infected",profile_stage);profile_stage=world.profiler.mark()
	# A teammate's hit can release a grab owned by another player's context.
	for context in contexts.values():
		if context.feedback.is_grabbed() and context.feedback.grabber.mode!="grab":
			context.bind(world);context.feedback.release("teammate");context.save(world)
	team_wiped=true
	for context in contexts.values():
		if not context.dead:team_wiped=false
	if restart_requested and team_wiped:restart_round()
	world.profiler.end_scope("server_team_state",profile_stage);profile_stage=world.profiler.mark()
	if tick%3==0:
		for id in ready_ids():_receive_snapshot.rpc_id(id,tick,roster_revision,all_states(),round_id)
	if tick%6==0:broadcast_bank()
	world.profiler.end_scope("server_snapshot_send",profile_stage)
	world.profiler.count("routes",world.navigation.queries_this_frame)
	server_tick_usec=Time.get_ticks_usec()-tick_started_usec;server_peak_usec=maxi(server_peak_usec,server_tick_usec)

func advance_player_commands(context,dt: float) -> void:
	var body=context.body
	# Credit is earned only by server physics time, never supplied by a client.
	# Brief missing input earns at most 100 ms; spend at most two steps/tick to
	# drain jitter backlog without allowing an unbounded speed-up exploit.
	body.movement_credit=minf(6.0,body.movement_credit+1.0)
	body.input_budget=minf(80.0,body.input_budget+1.0)
	var count:=mini(body.commands.size(),mini(int(body.movement_credit),2 if body.commands.size()>3 else 1))
	if count==0:
		body.axes=Vector2.ZERO;body.running=false;body.simulate(dt,tick);return
	for i in count:
		consume_input(body)
		if context.dead or context.feedback.is_grabbed():body.axes=Vector2.ZERO
		body.simulate(dt,tick);body.movement_credit-=1.0

func choose_target(enemy):
	for context in contexts.values():
		if context.feedback.grabber==enemy:return context
	var best=null;var distance:=INF
	for context in contexts.values():
		if context.dead:continue
		var candidate: float=enemy.position.distance_squared_to(context.body.position)
		if candidate<distance:best=context;distance=candidate
	return best if best!=null else contexts.values()[0]

func restart_round() -> void:
	restore_local();world.reset_fixture("default");round_id+=1;team_wiped=false
	for context in contexts.values():
		context.hp=100;context.dead=false;context.hurt_cooldown=0;context.strike_time=-1;context.strike_cooldown=0
		context.feedback.reset();context.weapon.reset("pistol");context.actions.clear()
		context.body.position=Vector3(23-float(context.body.slot)*.7,.05,8.2);context.body.velocity=Vector3.ZERO
		context.body.axes=Vector2.ZERO
	original_player.collision_layer=0
	broadcast_reset()

func broadcast_reset() -> void:
	for context in contexts.values():context.body.commands.clear();context.actions.clear()
	for id in ready_ids():_round_reset.rpc_id(id,round_id,tick,all_states())

@rpc("authority","call_remote","reliable",0)
func _round_reset(epoch: int,server_tick: int,rows: Array) -> void:
	if epoch<=received_round:return
	received_round=epoch;latest_tick=maxi(latest_tick,server_tick);bank_tick=maxi(bank_tick,server_tick-1)
	snapshot_buffer.reset();prediction.reset();input_history.clear();pending_reconcile.clear();preview_fire.clear()
	pending_actions.clear()
	world.reset_infected("default");replicas.clear();presentation.reset();world.feedback.reset();received_shots=-1
	for row in rows:
		if players.has(int(row.id)):players[int(row.id)].apply_snapshot(row,true)
		if int(row.id)==local_id:yaw=row.yaw;pitch=row.pitch
	held.clear();world.camera_motion.reset()
	if started:resume()

func broadcast_bank() -> void:
	var recipients:=ready_ids()
	if recipients.is_empty():return
	var states: Dictionary={}
	for id in contexts:states[id]=contexts[id].state()
	var doors: Dictionary={}
	for id in world.doors:
		var door=world.doors[id];doors[id]=[door.progress,door.target,door.swing,door.blocked]
	var enemies: Array=[]
	for enemy in world.infected:
		enemies.append([str(enemy.name),enemy.position,enemy.rotation.y,enemy.velocity,enemy.hp,enemy.mode,enemy.clock,enemy.state_time,enemy.active,
			enemy.ragdoll.positions.duplicate() if enemy.mode=="dead" else [],enemy.ragdoll.head_destroyed,enemy.animation_name,enemy.animation_time,enemy.native_motion.phase,enemy.attack_serial,enemy.reaction_time,enemy.reaction_duration,enemy.reaction_zone,enemy.reaction_direction,enemy.reaction_vector,enemy.reaction_strength,enemy.strong_reaction])
	var packet: Dictionary={"round":round_id,"team":states,"doors":doors,"enemies":enemies,"kills":world.kills,"wiped":team_wiped,"started":started,"leader":leader,"reserved":recovery.reservations.size()}
	var raw:=var_to_bytes(packet)
	var compressed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
	wire_bytes=compressed.size()
	var parts: Array=snapshot_buffer.shards(compressed);var count:=parts.size()-1
	for id in recipients:
		for index in parts.size():_bank_chunk.rpc_id(id,tick,index,count,raw.size(),compressed.size(),parts[index])
		if tick%60==6:_bank_keyframe.rpc_id(id,tick,raw.size(),compressed)

@rpc("authority","call_remote","reliable",2)
func _bank_keyframe(server_tick: int, size: int, bytes: PackedByteArray) -> void:
	if size<1 or size>1048576 or bytes.size()>115200:return
	var decoded=bytes_to_var(bytes.decompress(size,FileAccess.COMPRESSION_ZSTD))
	if decoded is Dictionary:_bank_snapshot(server_tick,decoded)

@rpc("authority","call_remote","unreliable",1)
func _bank_chunk(server_tick: int, index: int, count: int, size: int,wire_size: int,bytes: PackedByteArray) -> void:
	if is_host:return
	var decoded: Dictionary=snapshot_buffer.receive(server_tick,index,count,size,wire_size,bytes,Time.get_ticks_msec(),bank_tick)
	if not decoded.is_empty():_bank_snapshot(server_tick,decoded)

func _bank_snapshot(server_tick: int, packet: Dictionary) -> void:
	if is_host or server_tick<=bank_tick or not players.has(local_id):return
	if packet.get("round",-1)!=received_round:return
	last_bank_received_msec=Time.get_ticks_msec()
	bank_tick=server_tick;team=packet.team;team_wiped=packet.wiped
	reserved_count=int(packet.get("reserved",0))
	var was_started:=started
	started=packet.started;leader=packet.leader
	if not started and input_enabled:open_menu()
	elif started and not was_started:
		var auto_resume: bool=not recovery.retrying or recovery.was_playing
		recovery.connected()
		if auto_resume:resume()
	world.kills=packet.kills
	for id in packet.doors:
		var door=world.doors[id];var row: Array=packet.doors[id]
		if presentation.frames.is_empty():door.progress=row[0];door.apply_progress()
		door.target=row[1];door.swing=row[2];door.blocked=row[3]
	for row in packet.enemies:
		var enemy=world.get_node_or_null(NodePath(row[0]))
		if enemy==null:continue
		var old: Array=replicas.get(row[0],[])
		var fresh: bool=old.is_empty()
		if fresh:
			enemy.position=row[1];enemy.rotation.y=row[2];enemy.clock=row[6]
			enemy.native_motion.phase=row[13];enemy.native_motion.previous_position=enemy.global_position
		if fresh or enemy.mode!=row[5] or enemy.attack_serial!=row[14]:enemy.state_time=row[7]
		if fresh or float(row[15])<float(old[15])-.01:enemy.reaction_time=row[15]
		enemy.velocity=row[3];enemy.hp=row[4];enemy.mode=row[5];enemy.active=row[8];enemy.visible=row[8]
		var role: String=enemy.native_motion.clips.get(str(row[11]).trim_prefix("native/"),{}).get("role","")
		enemy.speed=3.0 if role=="run" else 1.0
		enemy.attack_serial=row[14];enemy.reaction_duration=row[16];enemy.reaction_zone=row[17];enemy.reaction_direction=row[18];enemy.reaction_vector=row[19];enemy.reaction_strength=row[20];enemy.strong_reaction=row[21]
		enemy.collision_layer=8 if enemy.mode!="dead" and enemy.active else 0
		if enemy.mode=="dead":
			if not enemy.ragdoll.active:enemy.ragdoll.start(Vector3.ZERO,enemy.position)
			if (fresh or old[5]!="dead") and row[9].size()==enemy.ragdoll.positions.size():enemy.ragdoll.positions.assign(row[9]);enemy.ragdoll.apply_pose()
			if row[10] and not enemy.ragdoll.head_destroyed:enemy.ragdoll.destroy_head()
		replicas[row[0]]=row
	presentation.push(server_tick,packet)
	for id in equipment:
		if team.has(id):
			var old_shots: int=equipment[id].last_shots
			equipment[id].update_state(team[id],players[id])
			if old_shots>=0 and team[id].shots>old_shots:equipment[id].shot_audio(world.firearms.audio)
			players[id].avatar.rotation.z=-PI/2 if team[id].dead else 0.0
	if team.has(local_id):
		var state: Dictionary=team[local_id];var weapon=world.firearms
		world.player_hp=state.hp;world.player_dead=state.dead
		if weapon.phase!=state.phase or state.time<weapon.phase_time-.15:weapon.event_flags.clear()
		weapon.selected=state.weapon;weapon.ammo=state.ammo;weapon.phase=state.phase;weapon.phase_time=state.time;weapon.duration=state.duration
		if state.weapon==local_fire_weapon and state.shots>local_fire_base and local_fire_age<3 and state.phase in ["fire","fire_last"]:
			weapon.phase_time=maxf(weapon.phase_time,local_fire_age)
		weapon.hit_time=state.hit;weapon.last_headshot=state.head;weapon.last_kill=state.kill;weapon.last_shot=state.last_shot
		if received_shots>=0 and state.shots>received_shots:
			if preview_fire.is_empty():weapon.flash_time=.05;weapon.play_sound(state.weapon);weapon.recoil.x=.035
			for impact in state.last_shot.get("impacts",[]):
				var p: Array=impact.position
				if not str(impact.enemy).is_empty():weapon.blood_fx.blood(Vector3(p[0],p[1],p[2]),Vector3.UP,-world.camera.global_basis.z,state.weapon,impact.head,state.kill,1,true)
				else:weapon.impact(Vector3(p[0],p[1],p[2]),Vector3.UP,false)
		weapon.shots=state.shots;received_shots=state.shots
		for serial in preview_fire.keys():
			if serial<=int(state.get("action_ack",0)) or Time.get_ticks_msec()-int(preview_fire[serial])>3000:preview_fire.erase(serial)
		world.feedback.damage_time=state.damage_time;world.feedback.damage_direction=state.damage_direction
		# Replica feedback is presentation only; never run bite logic on clients.
		world.feedback.grab_blend=1.0 if state.grabbed else 0.0
	if panel:panel.refresh()

func observe() -> Dictionary:
	var result:=super.observe()
	result.presentation=presentation.observe();result.mouse_mode=Input.mouse_mode;result.mouse_buttons=Input.get_mouse_button_mask()
	result.prediction=prediction.observe();result.snapshot_assembly=snapshot_buffer.observe()
	result.recovery={"retrying":recovery.retrying,"attempts":recovery.attempts,"resumed":recovery.resumed,"reserved":recovery.reservations.size(),"occupied":occupied_slots() if is_host else players.size()}
	result.network_stalled=network_stalled;result.preview_shots=preview_count
	result.merge({"active":active,"bank_tick":bank_tick,"round":round_id if is_host else received_round,"team_wiped":team_wiped,"local_server_pid":local_server_pid,
		"bank_scene":true,"started":started,"leader":leader,"aim":[yaw,pitch],"camera_rotation":world.camera.global_rotation,"wire_bytes":wire_bytes,"server_tick_usec":server_tick_usec,"server_peak_usec":server_peak_usec,"kills":world.kills})
	var states: Dictionary={}
	if is_host:
		for id in contexts:states[str(id)]=contexts[id].state()
	else:
		for id in team:states[str(id)]=team[id]
	result["combat"]=states
	result["enemies"]=[]
	for enemy in world.infected:result.enemies.append({"id":str(enemy.name),"hp":enemy.hp,"mode":enemy.mode,"active":enemy.active,"position":[enemy.position.x,enemy.position.y,enemy.position.z]})
	result["doors"]={}
	for id in world.doors:result.doors[id]=world.doors[id].state()
	result["equipment"]={}
	for id in equipment:result.equipment[str(id)]=equipment[id].observe()
	return result

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and active and not is_host and not testing:
		open_menu()

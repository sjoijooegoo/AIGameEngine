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
var chunk_tick := -1
var chunks: Dictionary={}
var ready_written := false
var last_bank_received_msec := 0
var lease_written_msec := -1000
var started := false
var leader := 0
var equipment: Dictionary={}
var remote_shots: Dictionary={}

func _ready() -> void:
	original_player=world.player;original_weapon=world.firearms;original_feedback=world.feedback
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
	var fingerprint:="bank-combat-v2"
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
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if panel:panel.refresh()

func resume() -> void:
	if not players.has(local_id):return
	input_enabled=true;world.ui.set_mode("play");Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	panel.refresh()

func restore_local() -> void:
	world.player=original_player;world.firearms=original_weapon;world.feedback=original_feedback

func disconnect_game(message: String="已退出会话") -> void:
	for context in contexts.values():context.weapon.queue_free()
	contexts.clear();restore_local()
	super.disconnect_game(message)
	equipment.clear();remote_shots.clear();chunks.clear();chunk_tick=-1
	team.clear();replicas.clear();bank_tick=-1;received_round=0;received_shots=-1;team_wiped=false
	started=false;leader=0;last_bank_received_msec=0
	world.player.collision_layer=2;world.player.collision_mask=9
	if panel:panel.refresh()

func leave_session() -> void:
	disconnect_game();launching=false
	if local_server_pid>0 and OS.is_process_running(local_server_pid):OS.kill(local_server_pid)
	local_server_pid=-1;world.reset_fixture("default");open_menu()

func back_to_solo() -> void:
	leave_session();active=false;panel.refresh();world.ui.set_mode("pause")

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
	if local_server_pid<=0:set_status("本地服务端启动失败");return
	launch_age=0;launching=true;set_status("正在加载本地银行服务端…")

func join_game(address: String, port_number: int, label: String) -> Error:
	active=true;world.ui.set_mode("play");world.ensure_infected()
	var result:=super.join_game(address,port_number,label)
	world.player.collision_layer=0;world.player.collision_mask=0
	for enemy in world.infected:enemy.visible=false;enemy.collision_layer=0;enemy.head_hitbox.collision_layer=0
	return result

func start_server(port_number: int, limit: int=4) -> Error:
	# Finish expensive actor setup before accepting ENet handshakes. Otherwise
	# the first client's RTT spike can throttle all its unreliable traffic.
	world.ensure_infected()
	return super.start_server(port_number,limit)

func prepare_player(body: CharacterBody3D) -> void:
	world.ensure_infected()
	if contexts.is_empty() and tick>0:
		restore_local();world.reset_fixture("default");round_id+=1
	body.position=Vector3(23.0-float(body.slot)*.7,.05,8.2);body.rotation.y=-1.120596
	var context=preload("res://coop/bank_peer.gd").new();context.setup(world,body);contexts[body.peer_id]=context
	if leader==0:leader=body.peer_id
	original_player.collision_layer=0

func _connected(id: int) -> void:
	if peer:peer.get_peer(id).set_timeout(32,2000,6000)
	super._connected(id)

func _disconnected(id: int) -> void:
	if contexts.has(id):
		var context=contexts[id];context.bind(world)
		if context.feedback.is_grabbed():context.feedback.release("disconnected")
		context.weapon.queue_free();contexts.erase(id);restore_local()
		if leader==id:leader=int(contexts.keys()[0]) if not contexts.is_empty() else 0
		if contexts.is_empty():started=false
	super._disconnected(id)

func _receive_roster(revision: int, rows: Array) -> void:
	super._receive_roster(revision,rows)
	for id in equipment.keys():
		if not players.has(id):equipment.erase(id)
	for id in players:
		if id!=local_id and not equipment.has(id):
			var visual=preload("res://coop/equipment.gd").new();players[id].add_child(visual);visual.setup(players[id]);equipment[id]=visual
	if players.has(local_id):
		original_player.position=players[local_id].position;original_player.rotation.y=yaw
		world.camera_motion.reset();world.ui.set_mode("play")
		if panel:panel.refresh()

func _input(_event: InputEvent) -> void:
	pass

func handle_event(event: InputEvent) -> void:
	if is_host:return
	if event is InputEventKey:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_ESCAPE and event.pressed and not event.echo:
			if input_enabled:open_menu();send_action("trigger",false)
			else:resume()
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
	action_sequence+=1
	_action.rpc_id(1,action_sequence,kind,value,yaw,pitch)

@rpc("any_peer","call_remote","reliable",0)
func _action(serial: int, kind: String, value: Variant, aim_yaw: float, aim_pitch: float) -> void:
	var id:=multiplayer.get_remote_sender_id()
	if not is_host or not contexts.has(id):return
	var context=contexts[id]
	if serial<=context.last_action or not is_finite(aim_yaw) or not is_finite(aim_pitch) or context.action_budget<1 or context.actions.size()>=40:return
	if kind not in ["trigger","shove","weapon","reload","door","struggle","restart","start"]:return
	if kind=="weapon" and value not in ["pistol","shotgun","torch","baton"]:return
	if kind=="struggle" and value not in [KEY_A,KEY_D]:return
	if kind in ["trigger","shove","reload","door","restart","start"] and not value is bool:return
	context.last_action=serial;context.action_budget-=1
	if kind=="start":
		if id==leader and contexts.size()>=2:started=true
		return
	context.actions.append([kind,value,wrapf(aim_yaw,-PI,PI),clampf(aim_pitch,-1.25,1.25)])

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
	if not is_host and players.has(local_id) and last_bank_received_msec>0 and Time.get_ticks_msec()-last_bank_received_msec>8000:
		disconnect_game("服务器响应超时，连接已断开");return
	if launching:
		launch_age+=dt
		if not OS.is_process_running(local_server_pid):launching=false;set_status("服务端未能启动，请检查端口是否占用")
		elif FileAccess.file_exists("user://coop_ready_"+str(OS.get_process_id())+".json"):
			launching=false;join_game("127.0.0.1",launch_port,player_name)
		elif launch_age>90:launching=false;set_status("本地服务端加载超时")
	if is_host:
		if owner_pid>0 and Time.get_unix_time_from_system()-FileAccess.get_modified_time("user://coop_owner_"+str(owner_pid)+".json")>15:
			get_tree().quit();return
		server_advance(dt);return
	super.advance(dt)
	if not players.has(local_id):return
	for id in equipment:equipment[id].advance(dt,players[id].aim_pitch)
	restore_local()
	var body=players[local_id]
	world.camera_motion.begin_tick();world.tick_count+=1
	world.player.position=body.position;world.player.rotation.y=yaw;world.player.velocity=body.velocity;world.pitch=pitch
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
	world.firearms.update_view(body.motion!="idle",world.sample_weapon_wall_distance(),dt)
	if world.firearms.selected=="torch":world.held_weapon.advance(world.tick_count,body.motion!="idle",world.sample_weapon_wall_distance())
	for enemy in world.infected:
		if not replicas.has(str(enemy.name)):continue
		var row: Array=replicas[str(enemy.name)]
		enemy.position=enemy.position.lerp(row[1],1-exp(-dt*18));enemy.rotation.y=lerp_angle(enemy.rotation.y,row[2],1-exp(-dt*18))
		if enemy.mode!="dead":enemy.clock+=dt;enemy.state_time+=dt;enemy.reaction_time+=dt;enemy.play_pose(dt)
	world.infected_audio.advance(dt);world.update_combat_ui()
	world.ui.hud.advance(dt);world.flashlight_lighting.advance(dt);world.door_lighting.advance();world.viewmodel_lighting.advance(dt)
	world.camera_motion.commit_tick()
	if panel:panel.refresh_hud()

func server_advance(dt: float) -> void:
	world.ensure_infected()
	if not ready_written and owner_pid>0:
		var file:=FileAccess.open("user://coop_ready_"+str(owner_pid)+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"pid":OS.get_process_id()}));file.close();ready_written=true
	if contexts.is_empty():return
	var tick_started_usec:=Time.get_ticks_usec()
	tick+=1;world.tick_count=tick;world.navigation.begin_frame()
	if not started:
		for context in contexts.values():context.actions.clear();context.body.axes=Vector2.ZERO
		if tick%6==0:broadcast_bank()
		return
	var restart_requested:=false
	var grabbed_hits: Dictionary={}
	for id in contexts:
		if contexts[id].feedback.is_grabbed():grabbed_hits[id]=contexts[id].feedback.grabber.hit_count
	for id in contexts:
		var context=contexts[id];context.bind(world);context.action_budget=minf(40,context.action_budget+dt*25)
		world.hurt_cooldown=maxf(0,world.hurt_cooldown-dt);world.strike_cooldown=maxf(0,world.strike_cooldown-dt)
		world.feedback.advance(dt,context.body.axes.length()>.1)
		for action in context.actions:
			if action[0]=="restart":restart_requested=true
			else:apply_action(context,action)
		context.actions.clear()
		if world.player_dead or world.feedback.is_grabbed():context.body.axes=Vector2.ZERO
		if tick-context.body.last_input_tick>18:world.firearms.clear_input()
		context.body.simulate(dt,tick);world.update_camera()
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
	for door in world.doors.values():door.advance(dt)
	world.navigation.update_doors();world.crowd.rebuild(world.infected)
	for enemy in world.infected:
		var target=choose_target(enemy)
		if target==null:continue
		target.bind(world);enemy.advance(dt);target.save(world)
		if enemy.active and enemy.mode!="dead":world.crowd.update(enemy)
	# A teammate's hit can release a grab owned by another player's context.
	for context in contexts.values():
		if context.feedback.is_grabbed() and context.feedback.grabber.mode!="grab":
			context.bind(world);context.feedback.release("teammate");context.save(world)
	team_wiped=true
	for context in contexts.values():
		if not context.dead:team_wiped=false
	if restart_requested and team_wiped:restart_round()
	if tick%3==0:_receive_snapshot.rpc(tick,roster_revision,all_states())
	if tick%6==0:broadcast_bank()
	server_tick_usec=Time.get_ticks_usec()-tick_started_usec;server_peak_usec=maxi(server_peak_usec,server_tick_usec)

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
	_round_reset.rpc(all_states())

@rpc("authority","call_remote","reliable",2)
func _round_reset(rows: Array) -> void:
	for row in rows:
		if players.has(int(row.id)):players[int(row.id)].apply_snapshot(row,true)
		if int(row.id)==local_id:yaw=row.yaw;pitch=row.pitch
	held.clear();world.camera_motion.reset()
	if started:resume()

func broadcast_bank() -> void:
	var states: Dictionary={}
	for id in contexts:states[id]=contexts[id].state()
	var doors: Dictionary={}
	for id in world.doors:
		var door=world.doors[id];doors[id]=[door.progress,door.target,door.swing,door.blocked]
	var enemies: Array=[]
	for enemy in world.infected:
		enemies.append([str(enemy.name),enemy.position,enemy.rotation.y,enemy.velocity,enemy.hp,enemy.mode,enemy.clock,enemy.state_time,enemy.active,
			enemy.ragdoll.positions.duplicate() if enemy.mode=="dead" else [],enemy.ragdoll.head_destroyed,enemy.animation_name,enemy.animation_time,enemy.native_motion.phase,enemy.attack_serial,enemy.reaction_time,enemy.reaction_duration,enemy.reaction_zone,enemy.reaction_direction,enemy.reaction_vector,enemy.reaction_strength,enemy.strong_reaction])
	var packet: Dictionary={"round":round_id,"team":states,"doors":doors,"enemies":enemies,"kills":world.kills,"wiped":team_wiped,"started":started,"leader":leader}
	var raw:=var_to_bytes(packet)
	var compressed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
	wire_bytes=compressed.size()
	var count:=ceili(float(compressed.size())/900.0)
	for index in count:_bank_chunk.rpc(tick,index,count,raw.size(),compressed.slice(index*900,(index+1)*900))
	if tick%60==6:_bank_keyframe.rpc(tick,raw.size(),compressed)

@rpc("authority","call_remote","reliable",2)
func _bank_keyframe(server_tick: int, size: int, bytes: PackedByteArray) -> void:
	if size<1 or size>1048576 or bytes.size()>115200:return
	var decoded=bytes_to_var(bytes.decompress(size,FileAccess.COMPRESSION_ZSTD))
	if decoded is Dictionary:_bank_snapshot(server_tick,decoded)

@rpc("authority","call_remote","unreliable",1)
func _bank_chunk(server_tick: int, index: int, count: int, size: int, bytes: PackedByteArray) -> void:
	if is_host or server_tick<=bank_tick or server_tick<chunk_tick or count<1 or count>128 or index<0 or index>=count or bytes.size()>900 or size<1 or size>1048576:return
	if server_tick>chunk_tick:chunks.clear();chunk_tick=server_tick
	chunks[index]=bytes
	if chunks.size()!=count:return
	var compressed:=PackedByteArray()
	for i in count:
		if not chunks.has(i):return
		compressed.append_array(chunks[i])
	var decoded=bytes_to_var(compressed.decompress(size,FileAccess.COMPRESSION_ZSTD))
	chunks.clear()
	if decoded is Dictionary:_bank_snapshot(server_tick,decoded)

func _bank_snapshot(server_tick: int, packet: Dictionary) -> void:
	if is_host or server_tick<=bank_tick or not players.has(local_id):return
	last_bank_received_msec=Time.get_ticks_msec()
	bank_tick=server_tick;team=packet.team;team_wiped=packet.wiped
	var was_started:=started
	started=packet.started;leader=packet.leader
	if not started and input_enabled:open_menu()
	elif started and not was_started:resume()
	if received_round!=packet.round:
		world.reset_infected("default");replicas.clear();received_round=packet.round
		world.feedback.reset();received_shots=-1
		for body in players.values():body.position=body.target_position
	world.kills=packet.kills
	for id in packet.doors:
		var door=world.doors[id];var row: Array=packet.doors[id]
		door.progress=row[0];door.target=row[1];door.swing=row[2];door.blocked=row[3];door.apply_progress()
	for row in packet.enemies:
		var enemy=world.get_node_or_null(NodePath(row[0]))
		if enemy==null:continue
		if not replicas.has(row[0]):enemy.position=row[1];enemy.rotation.y=row[2]
		enemy.velocity=row[3];enemy.hp=row[4];enemy.mode=row[5];enemy.clock=row[6];enemy.state_time=row[7];enemy.active=row[8];enemy.visible=row[8]
		enemy.native_motion.phase=row[13];enemy.attack_serial=row[14];enemy.reaction_time=row[15];enemy.reaction_duration=row[16];enemy.reaction_zone=row[17];enemy.reaction_direction=row[18];enemy.reaction_vector=row[19];enemy.reaction_strength=row[20];enemy.strong_reaction=row[21]
		enemy.collision_layer=8 if enemy.mode!="dead" and enemy.active else 0
		if enemy.mode=="dead":
			if not enemy.ragdoll.active:enemy.ragdoll.start(Vector3.ZERO,enemy.position)
			if row[9].size()==enemy.ragdoll.positions.size():enemy.ragdoll.positions.assign(row[9]);enemy.ragdoll.apply_pose()
			if row[10] and not enemy.ragdoll.head_destroyed:enemy.ragdoll.destroy_head()
		replicas[row[0]]=row
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
		weapon.hit_time=state.hit;weapon.last_headshot=state.head;weapon.last_kill=state.kill;weapon.last_shot=state.last_shot
		if received_shots>=0 and state.shots>received_shots:
			weapon.flash_time=.05;weapon.play_sound(state.weapon);weapon.recoil.x=.035
			for impact in state.last_shot.get("impacts",[]):
				var p: Array=impact.position
				if not str(impact.enemy).is_empty():weapon.blood_fx.blood(Vector3(p[0],p[1],p[2]),Vector3.UP,-world.camera.global_basis.z,state.weapon,impact.head,state.kill,1,true)
				else:weapon.impact(Vector3(p[0],p[1],p[2]),Vector3.UP,false)
		weapon.shots=state.shots;received_shots=state.shots
		world.feedback.damage_time=state.damage_time;world.feedback.damage_direction=state.damage_direction
		# Replica feedback is presentation only; never run bite logic on clients.
		world.feedback.grab_blend=1.0 if state.grabbed else 0.0
	if panel:panel.refresh()

func observe() -> Dictionary:
	var result:=super.observe()
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
	return result

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and active and not is_host and not testing:
		open_menu();send_action("trigger",false)

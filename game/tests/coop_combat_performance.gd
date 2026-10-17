extends "bank_coop_driver.gd"
## Debug-only bounded real-time route. Fixture placement is setup; combat uses
## ordinary InputEvents. No controller polling, captures or file I/O in samples.
var config: Dictionary={}
var run_config: Dictionary={}
var route_tick := 0
var telemetry: Array=[]
var start_state: Dictionary={}
var placement: Dictionary={}
var shadow_defaults: Dictionary={}
var measuring := false
var last_live_sample := -1
var phase_states: Array=[]
var previous_clips: Dictionary={}
var loaded_rounds: Dictionary={}

func boot() -> void:
	await super.boot()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0 if DisplayServer.get_name()!="headless" else 60
	AudioServer.set_bus_mute(0,true)
	for light in game.world.find_children("*","Light3D",true,false):shadow_defaults[light]=light.shadow_enabled

func _process(dt: float) -> bool:
	if run_config.is_empty():return super._process(dt)
	var now:=Time.get_unix_time_from_system()
	if measuring and telemetry.size()<60000:
		telemetry.append({"time":now,"world_tick":game.bank_tick,"world_age_ms":Time.get_ticks_msec()-game.last_bank_received_msec if game.last_bank_received_msec>0 else -1,
			"prediction_error":game.prediction.last_error,"wire_bytes":game.wire_bytes})
	if now>=float(run_config.start)+float(run_config.warmup)+float(run_config.seconds):
		finish_run()
	return false

func _physics_process(dt: float) -> bool:
	if run_config.is_empty():return false
	var elapsed:=Time.get_unix_time_from_system()-float(run_config.start)
	if elapsed<0:return false
	if not measuring and elapsed>=float(run_config.warmup):
		pop_network();start_state=outcome();telemetry.clear();phase_states.clear()
		game.world.profiler.start_recording();measuring=true
	var input_started:=Time.get_ticks_usec()
	if not game.is_host:drive_input()
	var input_usec:=Time.get_ticks_usec()-input_started
	game.world.advance(dt)
	if game.is_host:
		for id in game.contexts:
			var weapon=game.contexts[id].weapon
			for name in ["pistol","shotgun"]:
				var key: String=str(id)+"/"+name;var clip: int=weapon.ammo[name].clip
				if previous_clips.has(key) and clip>int(previous_clips[key]):loaded_rounds[key]=int(loaded_rounds.get(key,0))+clip-int(previous_clips[key])
				previous_clips[key]=clip
	if measuring and not game.world.profiler.ticks.is_empty():game.world.profiler.ticks[-1].route_input_ms=float(input_usec)/1000.0
	if measuring and int(elapsed)!=last_live_sample:
		last_live_sample=int(elapsed);phase_states.append(outcome())
	route_tick+=1
	return false

func key_event(code: int,down: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down
	event.set_meta("ai_bridge_input",true);Input.parse_input_event(event);Input.flush_buffered_events()

func mouse_button(code: int,down: bool) -> void:
	var event:=InputEventMouseButton.new();event.button_index=code;event.pressed=down
	event.set_meta("ai_bridge_input",true);Input.parse_input_event(event);Input.flush_buffered_events()

func release_input() -> void:
	for code in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_R,KEY_1,KEY_2]:key_event(code,false)
	mouse_button(MOUSE_BUTTON_LEFT,false);mouse_button(MOUSE_BUTTON_RIGHT,false)

func drive_input() -> void:
	if not game.players.has(game.local_id) or not game.input_enabled:return
	var slot: int=game.players[game.local_id].slot
	if route_tick==0:
		var weapon_key: int=KEY_2 if slot==1 else KEY_1
		key_event(weapon_key,true);key_event(weapon_key,false)
	# Bounded strafe/struggle and shove. No damage callback, refill or teleport.
	if route_tick%120==10:key_event(KEY_A,true)
	if route_tick%120==25:key_event(KEY_A,false)
	if route_tick%120==70:key_event(KEY_D,true)
	if route_tick%120==85:key_event(KEY_D,false)
	if route_tick%12==0 and game.team.get(game.local_id,{}).get("grabbed",false):
		var struggle_key: int=KEY_A if (route_tick/12)%2==0 else KEY_D
		key_event(struggle_key,true);key_event(struggle_key,false)
	var current_weapon=game.world.firearms
	var reload_threshold: int=2 if current_weapon.selected=="shotgun" else 3
	var allow_shove: bool=int(current_weapon.ammo[current_weapon.selected].clip)>reload_threshold and not current_weapon.phase.begins_with("reload") and current_weapon.phase!="insert_shell"
	if route_tick%60==30 and allow_shove:mouse_button(MOUSE_BUTTON_RIGHT,true)
	if route_tick%60==31:mouse_button(MOUSE_BUTTON_RIGHT,false)
	if route_tick%15==0:
		var best=null;var nearest:=INF
		var camera: Camera3D=game.world.camera
		for enemy in game.world.infected:
			if not enemy.active or enemy.mode=="dead":continue
			var delta: Vector3=enemy.global_position-camera.global_position
			if absf(delta.y)>3 or delta.length_squared()>=nearest:continue
			var query:=PhysicsRayQueryParameters3D.create(camera.global_position,enemy.global_position+Vector3.UP*1.1,1)
			if not game.world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():continue
			best=enemy;nearest=delta.length_squared()
		if best!=null:
			var delta: Vector3=best.global_position+Vector3.UP*1.1-camera.global_position
			var aim_yaw: float=atan2(-delta.x,-delta.z)-game.world.firearms.recoil.y-game.world.feedback.camera_rotation.y
			var aim_pitch: float=atan2(delta.y,Vector2(delta.x,delta.z).length())-game.world.firearms.recoil.x-game.world.feedback.camera_rotation.x
			var event:=InputEventMouseMotion.new()
			var sensitivity: float=.0025*float(game.world.ui.settings.sensitivity)
			event.relative=root.get_final_transform().basis_xform(Vector2(-wrapf(aim_yaw-game.yaw,-PI,PI)/sensitivity,-(aim_pitch-game.pitch)/sensitivity))
			event.set_meta("ai_bridge_input",true);Input.parse_input_event(event);Input.flush_buffered_events()
	# Fire after the previous shove's 0.52 s lock has elapsed.
	if route_tick%60==8+slot*3:
		var weapon=game.world.firearms
		if weapon.ammo[weapon.selected].clip<=reload_threshold:key_event(KEY_R,true);key_event(KEY_R,false)
		else:mouse_button(MOUSE_BUTTON_LEFT,true)
	if route_tick%60==10+slot*3:mouse_button(MOUSE_BUTTON_LEFT,false)

func clear_at(body: CharacterBody3D,point: Vector3) -> bool:
	var shape: CollisionShape3D=body.get_children().filter(func(n):return n is CollisionShape3D)[0]
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape
	query.transform=Transform3D(Basis.IDENTITY,point)*shape.transform;query.collision_mask=1;query.margin=.005
	return game.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func candidates_for(area: Array) -> Array:
	var result: Array=[]
	for id in game.world.navigation.graph.get_point_ids():
		var p: Vector3=game.world.navigation.graph.get_point_position(id)+Vector3.UP*.04
		if absf(p.y-float(config.floor))<.18 and p.x>=area[0] and p.z>=area[1] and p.x<=area[2] and p.z<=area[3]:result.append(p)
	return result

func setup_fixture(value: Dictionary) -> Dictionary:
	assert(game.is_host)
	config=value;game.restore_local();game.world.ensure_infected();game.world.reset_fixture("default")
	game.round_id+=1;game.team_wiped=false
	var points:=candidates_for(config.area);var occupied: Array=[];var entries: Array=[]
	var center:=Vector3(config.player[0],config.floor,config.player[1])
	for context in game.contexts.values():
		points.sort_custom(func(a,b):return a.distance_squared_to(center)<b.distance_squared_to(center))
		var selected:=Vector3.INF
		for p in points:
			if occupied.any(func(q):return p.distance_to(q)<1.0) or not clear_at(context.body,p):continue
			selected=p;break
		assert(selected!=Vector3.INF,"No clear player placement")
		context.hp=10000;context.dead=false;context.feedback.reset();context.weapon.reset("pistol")
		context.weapon.rng.seed=52831+context.body.slot
		context.hurt_cooldown=0;context.strike_cooldown=0;context.strike_time=-1;context.actions.clear()
		context.body.position=selected;context.body.rotation.y=0;context.body.aim_pitch=0;context.body.velocity=Vector3.ZERO;context.body.axes=Vector2.ZERO
		occupied.append(selected);entries.append({"role":"player","slot":context.body.slot,"position":selected})
	var enemy_center:=Vector3((config.area[0]+config.area[2])*.5,config.floor,(config.area[1]+config.area[3])*.5)
	points.sort_custom(func(a,b):return a.distance_squared_to(enemy_center)<b.distance_squared_to(enemy_center))
	for i in game.world.infected.size():
		var actor=game.world.infected[i];actor.active=i<int(config.population);actor.visible=actor.active
		actor.collision_layer=8 if actor.active else 0;actor.head_hitbox.collision_layer=16 if actor.active else 0
		if not actor.active:continue
		var selected:=Vector3.INF
		for p in points:
			if p.distance_to(center)<2.5 or occupied.any(func(q):return p.distance_to(q)<1.05) or not clear_at(actor,p):continue
			selected=p;break
		if selected==Vector3.INF:return {"error":"Insufficient clear enemy placements","placed":i,"wanted":config.population,"candidates":points.size()}
		actor.position=selected;actor.home=selected;actor.anchored=false;actor.path.clear();actor.path_timer=0
		actor.rotation.y=atan2(selected.x-center.x,selected.z-center.z);actor.play_pose(0)
		occupied.append(selected);entries.append({"role":"enemy","name":str(actor.name),"position":selected})
	game.original_player.collision_layer=0;game.world.crowd.rebuild(game.world.infected)
	game.broadcast_reset()
	placement={"entries":entries,"world_overlaps":0,"minimum_separation":1.05,"population":config.population,"allocated":game.world.infected.size(),"diagnostic_player_hp":10000,"seed":52831}
	return placement

func outcome() -> Dictionary:
	var result:={"tick":game.tick if game.is_host else game.world.tick_count,"world_tick":game.bank_tick,"players":game.players.size(),"kills":game.world.kills,"alive":0,"awake_corpses":0,"sleeping_corpses":0,"combat":{},"active":0}
	for actor in game.world.infected:
		if not actor.active:continue
		result.active+=1
		if actor.mode!="dead":result.alive+=1
		elif actor.ragdoll.sleeping:result.sleeping_corpses+=1
		else:result.awake_corpses+=1
	var source: Dictionary=game.contexts if game.is_host else game.team
	result.loaded_rounds=loaded_rounds.duplicate()
	for id in source:
		var state: Dictionary=source[id].state() if game.is_host else source[id]
		result.combat[str(id)]={"hp":state.hp,"dead":state.dead,"shots":state.shots,"weapon":state.weapon,"ammo":state.ammo}
	return result

func pop_network() -> Dictionary:
	var result:={}
	if game.peer==null:return result
	for k in {"sent_bytes":ENetConnection.HOST_TOTAL_SENT_DATA,"received_bytes":ENetConnection.HOST_TOTAL_RECEIVED_DATA,"sent_packets":ENetConnection.HOST_TOTAL_SENT_PACKETS,"received_packets":ENetConnection.HOST_TOTAL_RECEIVED_PACKETS}:
		var stat: int={"sent_bytes":0,"received_bytes":2,"sent_packets":1,"received_packets":3}[k]
		result[k]=game.peer.host.pop_statistic(stat)
	return result

func finish_run() -> void:
	var data: Dictionary=game.world.profiler.stop_recording()
	data.config=config;data.role="server" if game.is_host else "client";data.start=start_state;data.finish=outcome()
	data.network=pop_network();data.telemetry=telemetry;data.phase_states=phase_states;data.placement=placement
	data.schedule=run_config.duplicate();data.route_ticks=route_tick
	measuring=false;run_config={};release_input()
	write_json("result.json",data)

func execute(request: Dictionary) -> void:
	var result: Dictionary={}
	match request.command:
		"perf_fixture":result=setup_fixture(request.config)
		"perf_config":
			config=request.config
			if DisplayServer.get_name()!="headless":DisplayServer.window_set_size(Vector2i(config.resolution[0],config.resolution[1]))
			for light in shadow_defaults:light.shadow_enabled=shadow_defaults[light] and not config.get("no_shadows",false)
			root.scaling_3d_scale=float(config.get("render_scale",1.0))
		"perf_status":result=outcome();result.round=game.round_id if game.is_host else game.received_round;result.started=game.started
		"perf_run":
			assert(request.warmup>=2 and request.warmup<=10 and request.seconds>=5 and request.seconds<=60)
			release_input();run_config={"start":request.start,"warmup":request.warmup,"seconds":request.seconds};route_tick=0;last_live_sample=-1;measuring=false;previous_clips.clear();loaded_rounds.clear()
		_:await super.execute(request);return
	write_json("response.json",{"id":request.id,"result":result});busy=false

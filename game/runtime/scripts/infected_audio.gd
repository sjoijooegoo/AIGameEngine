extends Node
## Bounded positional voices, driven by combat events and travelled distance.
## No audio random draw is shared with combat or pathfinding.
const CAPS := {"vocal":6,"body":4}
const RAY_BUDGET := 2
const MIX=preload("res://scripts/audio_mix.gd")
var world: Node3D
var bank: Dictionary
var streams: Dictionary={}
var profile_streams: Dictionary={}
var voices: Array=[]
var actors: Dictionary={}
var pending: Array=[]
var history: Array=[]
var rng:=RandomNumberGenerator.new()
var clock := 0.0
var periodic_time := 0.0
var serial := 0
var dropped := 0
var peak_voices := 0
var peak_rays := 0
var rays := 0
var ray_cursor := 0
var enabled := true

func setup(game: Node3D) -> void:
	world=game
	MIX.setup_buses()
	if AudioServer.get_bus_index("InfectedMuffled")<0:
		AudioServer.add_bus();var i:=AudioServer.bus_count-1;AudioServer.set_bus_name(i,"InfectedMuffled");AudioServer.set_bus_send(i,"InfectedSFX")
		var lowpass:=AudioEffectLowPassFilter.new();lowpass.cutoff_hz=1700;AudioServer.add_bus_effect(i,lowpass)
	bank=JSON.parse_string(FileAccess.get_file_as_string("res://audio/infected/bank.json"))
	for key in bank.events:
		streams[key]=[]
		for path in bank.events[key].files:streams[key].append(load(path))
	for character in bank.get("profiles",{}):
		profile_streams[character]={}
		for key in bank.profiles[character]:
			profile_streams[character][key]=[]
			for path in bank.profiles[character][key]:profile_streams[character][key].append(load(path))
	for group in CAPS:
		for i in CAPS[group]:
			var player:=AudioStreamPlayer3D.new();player.bus="InfectedSFX";player.max_polyphony=1
			player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED;player.max_distance=0
			player.attenuation_filter_cutoff_hz=20500;player.panning_strength=.85
			world.add_child(player)
			voices.append({"player":player,"group":group,"until":0.0,"owner":null,"key":"","priority":0,"blocked":false,"checked":false,"query_at":0.0,"gain":-80.0,"base_gain":-80.0,"distance":0.0})
	reset()

func reset() -> void:
	clock=0;periodic_time=0;serial=0;dropped=0;peak_voices=0;peak_rays=0;rays=0;ray_cursor=0;rng.seed=671504
	actors.clear();pending.clear();history.clear()
	for voice in voices:stop_voice(voice)

func stop_voice(voice: Dictionary) -> void:
	if is_instance_valid(voice.player):voice.player.stop()
	voice.until=0.0;voice.owner=null;voice.key="";voice.checked=false

func actor_state(actor: Node3D) -> Dictionary:
	var id: String=actor.definition.id
	if not actors.has(id):
		var stagger: float=float(posmod(id.hash(),997))/997.0
		actors[id]={"last":{},"cooldowns":{},"periodic_at":clock+.8+stagger*3.5,"position":actor.global_position,"stride":0.0}
	return actors[id]

func request(actor: Node3D,key: String) -> void:
	if not enabled or not actor.active or not bank.events.has(key):return
	if actor.mode=="dead" and key!="death":return
	var spec: Dictionary=bank.events[key]
	if actor.global_position.distance_to(world.player.global_position)>float(spec.range):return
	var state:=actor_state(actor)
	if clock<float(state.cooldowns.get(key,-1)):return
	for item in pending:
		if item.actor==actor and item.key==key:return
	if key=="death":
		for voice in voices:
			if voice.owner==actor:stop_voice(voice)
		pending=pending.filter(func(e):return e.actor!=actor)
	# A bound prevents a simultaneous crowd transition from growing work.
	if pending.size()>=64:dropped+=1;return
	state.cooldowns[key]=clock+float(spec.cooldown)
	pending.append({"actor":actor,"key":key,"priority":int(spec.priority),"distance":actor.global_position.distance_to(world.player.global_position)})

func profile(actor: Node3D) -> String:
	if actor.definition.type=="fastElite":return "hunter"
	if actor.definition.type=="boss":return "tank"
	if actor.stats.get("heavy",false):return "heavy"
	if str(actor.definition.model).begins_with("female"):return "higher"
	if actor.definition.type=="runner":return "runner"
	return "common"

func mouth(actor: Node3D,key: String) -> Vector3:
	if key=="step":return actor.global_position+Vector3.UP*.15
	return actor.head_hitbox.global_position

func play_request(item: Dictionary) -> void:
	var actor: Node3D=item.actor;var key: String=item.key
	if not actor.active or (actor.mode=="dead" and key!="death"):return
	var spec: Dictionary=bank.events[key];var chosen: Dictionary={};var same: Dictionary={}
	var ambience:=0
	for voice in voices:
		if voice.until>clock and voice.key in ["idle","chase"]:ambience+=1
		if voice.group!=spec.group:continue
		if voice.until>clock and voice.owner==actor:
			if voice.priority>item.priority:return
			same=voice
		if chosen.is_empty() and voice.until<=clock:chosen=voice
	if key in ["idle","chase"] and ambience>=2:dropped+=1;return
	if not same.is_empty():chosen=same
	if chosen.is_empty():
		for voice in voices:
			if voice.group==spec.group and voice.priority<item.priority:
				if chosen.is_empty() or voice.priority<chosen.priority or (voice.priority==chosen.priority and voice.distance>chosen.distance):chosen=voice
	if chosen.is_empty():dropped+=1;return
	stop_voice(chosen)
	var character:=profile(actor)
	var state:=actor_state(actor);var list: Array=profile_streams.get(character,{}).get(key,streams[key]);var index:=rng.randi_range(0,list.size()-1)
	if list.size()>1 and index==int(state.last.get(key,-1)):index=(index+1+rng.randi_range(0,list.size()-2))%list.size()
	state.last[key]=index
	var base_pitch: float=.95 if character=="heavy" and spec.group=="vocal" else 1.0
	var pitch:=base_pitch*rng.randf_range(.97,1.03)
	chosen.owner=actor;chosen.key=key;chosen.priority=item.priority;chosen.duration=list[index].get_length()/pitch;chosen.until=clock+chosen.duration;chosen.started=false
	var calibration_db: float=MIX.trim("infected",key,list[index].resource_path)
	chosen.base_gain=float(spec.gain_db)+rng.randf_range(-.6,.6)+calibration_db;chosen.blocked=false;chosen.checked=false;chosen.query_at=clock
	chosen.player.global_position=mouth(actor,key);chosen.player.pitch_scale=pitch;chosen.player.stream=list[index]
	# Start quiet until a bounded visibility query has established the path.
	chosen.gain=-80;chosen.player.volume_db=-80
	serial+=1
	history.append({"serial":serial,"id":str(actor.definition.id),"key":key,"variant":index,"profile":character,"resource":list[index].resource_path,"pitch":pitch,"calibration_db":calibration_db,"time":clock,"state":actor.mode})
	if history.size()>128:history.pop_front()

func periodic() -> void:
	for actor in world.infected:
		if not actor.active or actor.mode=="dead":continue
		var state:=actor_state(actor)
		var moved: Vector3=actor.global_position-state.position;state.position=actor.global_position
		if actor.global_position.distance_squared_to(world.player.global_position)>400:state.stride=0;continue
		if actor.mode in ["chase","return"] and actor.is_on_floor():
			state.stride+=minf(.65,Vector2(moved.x,moved.z).length())
			if state.stride>(.85 if actor.speed>2 else .52):state.stride=0;request(actor,"step")
		else:state.stride=0
		if clock>=float(state.periodic_at):
			state.periodic_at=clock+rng.randf_range(3.2,5.8) if actor.mode=="chase" else clock+rng.randf_range(6.0,10.0)
			if actor.mode in ["idle","return"]:request(actor,"idle")
			elif actor.mode=="chase":request(actor,"chase")

func advance(dt: float) -> void:
	var started: int=world.profiler.mark()
	clock+=dt;rays=0;periodic_time-=dt
	if periodic_time<=0:periodic_time=.1;periodic()
	pending.sort_custom(func(a,b):return a.priority>b.priority if a.priority!=b.priority else a.distance<b.distance)
	for item in pending:play_request(item)
	pending.clear()
	# At most two static-world rays per tick, independent of the 84-actor count.
	for offset in voices.size():
		var index: int=(ray_cursor+offset)%voices.size();var voice: Dictionary=voices[index]
		if voice.until<=clock or not is_instance_valid(voice.owner) or clock<voice.query_at:continue
		var pos:=mouth(voice.owner,voice.key)
		var query:=PhysicsRayQueryParameters3D.create(world.camera.global_position,pos,1)
		voice.blocked=not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		voice.checked=true;voice.query_at=clock+.18;rays+=1
		if rays>=RAY_BUDGET:ray_cursor=(index+1)%voices.size();break
	var active:=0
	for voice in voices:
		if voice.until<=clock:continue
		if not is_instance_valid(voice.owner) or not voice.owner.active or (voice.owner.mode=="dead" and voice.key!="death"):stop_voice(voice);continue
		voice.player.global_position=mouth(voice.owner,voice.key)
		voice.distance=voice.player.global_position.distance_to(world.camera.global_position)
		var target: float=voice.base_gain-20.0*log(1.0+voice.distance/2.0)/log(10.0)-(12.0 if voice.blocked else 0.0)
		if not voice.checked or voice.distance>float(bank.events[voice.key].range):target=-80.0
		if voice.checked and not voice.started:
			voice.started=true;voice.until=clock+voice.duration;voice.gain=target
			voice.player.volume_db=target;voice.player.bus="InfectedMuffled" if voice.blocked else "InfectedSFX"
			if DisplayServer.get_name()!="headless":voice.player.play()
		else:voice.gain=move_toward(voice.gain,target,dt*100)
		voice.player.volume_db=voice.gain
		voice.player.bus="InfectedMuffled" if voice.blocked else "InfectedSFX"
		active+=1
	peak_voices=maxi(peak_voices,active);peak_rays=maxi(peak_rays,rays)
	world.profiler.count("infected_audio_voices",active);world.profiler.count("infected_audio_rays",rays);world.profiler.end_scope("infected_audio",started)

func observe() -> Dictionary:
	var live: Array=[]
	for voice in voices:
		if voice.until>clock and is_instance_valid(voice.owner):
			var local: Vector3=world.camera.to_local(voice.player.global_position)
			live.append({"id":str(voice.owner.definition.id),"key":voice.key,"distance":voice.distance,"gain_db":voice.gain,"occluded":voice.blocked,"checked":voice.checked,"local_x":local.x,"remaining":voice.until-clock})
	return {"clock":clock,"serial":serial,"events":history.duplicate(true),"voices":live,"voice_cap":10,"peak_voices":peak_voices,"dropped":dropped,"rays":rays,"peak_rays":peak_rays,"ray_cap":RAY_BUDGET,"master_ceiling_db":MIX.ceiling("GameSFX"),"mix_revision":MIX.revision()}

func _exit_tree() -> void:
	for voice in voices:
		if is_instance_valid(voice.player):voice.player.stop()

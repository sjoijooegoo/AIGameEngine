extends Node
## One bounded voice per playback: pitch/stream changes never retune older tails.
## This RNG is intentionally independent from gun spread and combat effects.
const BUS := "WeaponSFX"
const MIX=preload("res://scripts/audio_mix.gd")
# Native P220 tails last 1.004 s (room return 1.054 s) at a 0.18 s
# fire interval. Six slots preserve the original decay under rapid fire.
const LIMITS := {"shot":6,"room":6,"mechanical":4,"impact":6}
var bank: Dictionary
var streams: Dictionary={}
var voices: Dictionary={}
var last_variant: Dictionary={}
var rng:=RandomNumberGenerator.new()
var clock := 0.0
var serial := 0
var stolen := 0
var events: Array=[]
var peak_voices := 0

func setup() -> void:
	bank=JSON.parse_string(FileAccess.get_file_as_string("res://audio/firearms/bank.json"))
	MIX.setup_buses()
	for key in bank.events:
		var variants: Array=[]
		for path in bank.events[key].files:variants.append(load(path))
		streams[key]=variants
	for group in LIMITS:
		var pool: Array=[]
		for i in LIMITS[group]:
			var player:=AudioStreamPlayer.new();player.bus=BUS;player.max_polyphony=1
			add_child(player);pool.append({"player":player,"until":0.0,"serial":0,"key":""})
		voices[group]=pool
	reset()

func reset() -> void:
	clock=0;stop_all();serial=0;stolen=0;peak_voices=0;events.clear();last_variant.clear();rng.seed=260613

func stop_all() -> void:
	for pool in voices.values():
		for voice in pool:
			if is_instance_valid(voice.player):voice.player.stop()
			voice.until=clock;voice.key=""

func cancel_mechanical() -> void:
	# Switching, a shove or a grab must not leave reload handling continuing.
	for voice in voices.get("mechanical",[]):voice.player.stop();voice.until=clock;voice.key=""

func advance(dt: float) -> void:clock+=dt

func play_event(key: String,gain: float=0,indoor: bool=true) -> void:
	if not bank.events.has(key):push_error("Unknown weapon audio event: "+key);return
	var spec: Dictionary=bank.events[key]
	var variants: Array=streams[key]
	var choice:=rng.randi_range(0,variants.size()-1)
	if variants.size()>1 and choice==int(last_variant.get(key,-1)):choice=(choice+1+rng.randi_range(0,variants.size()-2))%variants.size()
	last_variant[key]=choice
	var pitch: float=rng.randf_range(spec.pitch[0],spec.pitch[1])
	var calibration_db: float=MIX.trim("firearms",key,variants[choice].resource_path)
	var db: float=float(spec.gain_db)+gain+rng.randf_range(-.45,.45)+calibration_db
	var pool: Array=voices[spec.group];var selected: Dictionary=pool[0];var free:=false
	for voice in pool:
		if float(voice.until)<=clock:selected=voice;free=true;break
		if float(voice.until)<float(selected.until):selected=voice
	if not free:stolen+=1
	serial+=1;selected.until=clock+variants[choice].get_length()/pitch;selected.serial=serial;selected.key=key
	var player: AudioStreamPlayer=selected.player
	if DisplayServer.get_name()!="headless":
		player.stop();player.stream=variants[choice];player.pitch_scale=pitch;player.volume_db=db;player.play()
	var active:=0
	for group in voices.values():
		for voice in group:
			if float(voice.until)>clock:active+=1
	peak_voices=maxi(peak_voices,active)
	events.append({"key":key,"variant":choice,"resource":variants[choice].resource_path,"pitch":pitch,"gain_db":db,"calibration_db":calibration_db,"time":clock,"serial":serial,"indoor":indoor})
	if events.size()>96:events.pop_front()
	# Room reflections are a separate quiet layer. The dry blast stays centred;
	# the outdoor yard never gets the bank interior's short stereo return.
	if key in ["pistol","shotgun"] and indoor:play_event(key+"_room",gain,indoor)

func observe() -> Dictionary:
	var active:=0
	for pool in voices.values():
		for voice in pool:
			if float(voice.until)>clock:active+=1
	var limit:=0
	for count in LIMITS.values():limit+=int(count)
	return {"serial":serial,"events":events.duplicate(true),"active_voices":active,"peak_voices":peak_voices,"voice_limit":limit,"stolen":stolen,"bus":BUS,"limiter_db":MIX.ceiling(BUS),"mix_revision":MIX.revision()}

func _exit_tree() -> void:stop_all()

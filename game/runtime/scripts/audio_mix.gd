extends RefCounted
## One project mix policy. Offline measurements supply static, per-event trims;
## playback only performs a dictionary lookup, with no new DSP/analysis per frame.
const STANDARD_PATH := "res://data/audio_standard.json"
const CALIBRATION_PATH := "res://data/audio_calibration.json"
static var standard: Dictionary={}
static var calibration: Dictionary={}
static var warned: Dictionary={}

static func load_policy() -> void:
	if not standard.is_empty():return
	standard=JSON.parse_string(FileAccess.get_file_as_string(STANDARD_PATH))
	calibration=JSON.parse_string(FileAccess.get_file_as_string(CALIBRATION_PATH))
	if calibration.revision!=standard.revision or calibration.standard_sha256!=FileAccess.get_sha256(STANDARD_PATH):
		push_error("Audio calibration must match the mix standard");calibration.trims={}
	for bank in standard.banks:
		if calibration.bank_hashes.get(bank,"")!=FileAccess.get_sha256(standard.banks[bank].resource):
			push_error("Audio bank changed without calibration: "+bank);calibration.trims[bank]={}

static func setup_buses() -> void:
	load_policy()
	for label in standard.buses:
		var spec: Dictionary=standard.buses[label]
		var index:=AudioServer.get_bus_index(label)
		if index<0:
			AudioServer.add_bus();index=AudioServer.bus_count-1;AudioServer.set_bus_name(index,label)
		AudioServer.set_bus_send(index,spec.send)
		var limiter: AudioEffectHardLimiter=null
		for effect in AudioServer.get_bus_effect_count(index):
			if AudioServer.get_bus_effect(index,effect) is AudioEffectHardLimiter:limiter=AudioServer.get_bus_effect(index,effect);break
		if limiter==null:limiter=AudioEffectHardLimiter.new();AudioServer.add_bus_effect(index,limiter)
		limiter.ceiling_db=float(spec.limiter_db);limiter.pre_gain_db=0;limiter.release=.08

static func trim(bank: String,event: String,path: String) -> float:
	load_policy()
	var variants: Dictionary=calibration.trims.get(bank,{}).get(event,{})
	if variants.has(path):return float(variants[path])
	# A newly added sound must be calibrated before it joins the mix. Keep an
	# unreviewed asset quiet and warn once, rather than reverting to full gain.
	var key:=bank+"/"+event+"/"+path
	if not warned.has(key):warned[key]=true;push_warning("Uncalibrated audio: "+key+"; run game.tools.calibrate_audio")
	return -18.0

static func ceiling(bus: String) -> float:
	load_policy();return float(standard.buses[bus].limiter_db)

static func revision() -> String:
	load_policy();return str(standard.revision)

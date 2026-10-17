extends Node
## Opt-in, bounded telemetry. CPU scopes are inclusive script time; wall-frame
## intervals and viewport GPU timings are separate quantities, never summed.
const MAX_SAMPLES := 60000
var enabled := false
var recording := false
var frames: Array = []
var ticks: Array = []
var scopes: Dictionary = {}
var counts: Dictionary = {}
var latest_tick: Dictionary = {}
var latest_frame: Dictionary = {}
var viewports: Dictionary = {}
var last_frame_usec := 0
var tick_started := 0
var record_started := 0
var duration_limit := 0.0
var output_path := ""
var recording_root := "user://performance"
var dropped := 0
var hud: Label
var hud_clock := 0.0

func _ready() -> void:
	set_process(false)
	register_viewport("world",get_viewport())

func register_viewport(label: String, viewport: Viewport) -> void:
	viewports[label]=viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewports[label],enabled)

func set_enabled(value: bool) -> void:
	enabled=value;last_frame_usec=0;set_process(value)
	for rid in viewports.values():RenderingServer.viewport_set_measure_render_time(rid,value)

func begin_tick() -> void:
	if not enabled:return
	tick_started=Time.get_ticks_usec();scopes.clear();counts.clear()

func mark() -> int:
	return Time.get_ticks_usec() if enabled else 0

func end_scope(label: String, started: int) -> void:
	if enabled:scopes[label]=float(scopes.get(label,0.0))+(Time.get_ticks_usec()-started)/1000.0

func count(label: String, amount: int=1) -> void:
	if enabled:counts[label]=int(counts.get(label,0))+amount

func end_tick() -> void:
	if not enabled:return
	latest_tick={"elapsed_ms":(Time.get_ticks_usec()-tick_started)/1000.0,"scopes_ms":scopes.duplicate(),"counts":counts.duplicate()}
	if recording:
		if ticks.size()<MAX_SAMPLES:ticks.append(latest_tick)
		else:dropped+=1

func start_recording(seconds: float=0.0, path: String="") -> void:
	frames.clear();ticks.clear();dropped=0;latest_tick={};record_started=Time.get_ticks_usec()
	duration_limit=seconds;output_path=path;recording=true;set_enabled(true)

func stop_recording() -> Dictionary:
	recording=false
	var result: Dictionary={"schema_version":1,"frames":frames.duplicate(),"ticks":ticks.duplicate(),"dropped_samples":dropped,
		"wall_seconds":(Time.get_ticks_usec()-record_started)/1000000.0,"environment":environment(),
		"semantics":{"frame_ms":"wall interval between rendered process frames; includes pacing/OS scheduling",
		"elapsed_ms":"script advance CPU only; scopes are inclusive and may overlap",
		"viewport_gpu_ms":"per viewport delayed GPU timestamps; zero means unavailable, not zero cost"}}
	if not output_path.is_empty():
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var file:=FileAccess.open(output_path,FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(result));print("PERFORMANCE_RECORD ",ProjectSettings.globalize_path(output_path))
		else:push_error("Cannot write performance capture: "+output_path)
	if hud==null or not hud.visible:set_enabled(false)
	return result

func environment() -> Dictionary:
	return {"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),
		"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_video_adapter_api_version(),
		"cpu":OS.get_processor_name(),"resolution":[get_viewport().size.x,get_viewport().size.y],
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,
		"debug":OS.is_debug_build(),"headless":DisplayServer.get_name()=="headless",
		"msaa_3d":get_viewport().msaa_3d,"screen_space_aa":get_viewport().screen_space_aa,"render_scale":get_viewport().scaling_3d_scale}

func _process(dt: float) -> void:
	var now:=Time.get_ticks_usec()
	if last_frame_usec>0:
		latest_frame={"frame_ms":(now-last_frame_usec)/1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,
			"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"video_memory_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,
			"static_memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"viewport_gpu_ms":{},"viewport_render_cpu_ms":{}}
		for label in viewports:
			latest_frame.viewport_gpu_ms[label]=RenderingServer.viewport_get_measured_render_time_gpu(viewports[label])
			latest_frame.viewport_render_cpu_ms[label]=RenderingServer.viewport_get_measured_render_time_cpu(viewports[label])
		if recording:
			if frames.size()<MAX_SAMPLES:frames.append(latest_frame)
			else:dropped+=1
	last_frame_usec=now
	hud_clock+=dt
	if hud!=null and hud.visible and hud_clock>=.25:
		hud_clock=0
		hud.text="F8 性能面板 · F9 录制 15 秒%s\n帧 %.1f ms · 脚本 %.1f ms · 绘制 %d\n感染者 %.1f · 骨骼 %.1f · 命中体 %.1f · 尸体 %.1f ms" % [" [录制中]" if recording else "",latest_frame.get("frame_ms",0),latest_tick.get("elapsed_ms",0),latest_frame.get("draw_calls",0),scopes.get("infected",0),scopes.get("pose",0),scopes.get("hitboxes",0),scopes.get("ragdoll",0)]
	if recording and duration_limit>0 and (now-record_started)/1000000.0>=duration_limit:stop_recording()

func toggle_hud() -> void:
	if hud==null:
		var layer:=CanvasLayer.new();layer.layer=100;add_child(layer)
		hud=Label.new();hud.position=Vector2(18,65);hud.add_theme_font_size_override("font_size",17)
		hud.add_theme_color_override("font_shadow_color",Color.BLACK);hud.add_theme_constant_override("shadow_outline_size",5)
		layer.add_child(hud);hud.visible=false
	hud.visible=not hud.visible;set_enabled(recording or hud.visible)

func manual_record() -> void:
	if recording:stop_recording()
	else:start_recording(15.0,recording_root.path_join("%s-%s.json" % [Time.get_datetime_string_from_system().replace(":","-"),Time.get_ticks_msec()]))

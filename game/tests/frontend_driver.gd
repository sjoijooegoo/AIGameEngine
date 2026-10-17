extends SceneTree
## Debug-only local UI harness. All navigation uses native input handlers.
var session_dir := ""
var busy := false

func _initialize() -> void:
	if not OS.is_debug_build():quit(2);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-session="):session_dir=arg.trim_prefix("--test-session=")
	if session_dir.is_empty() or not DirAccess.dir_exists_absolute(session_dir):quit(2);return
	boot.call_deferred()

func boot() -> void:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await process_frame
	write_json("ready.json",{"ready":true})

func write_json(filename: String,data: Dictionary) -> void:
	var path:=session_dir.path_join(filename)
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	DirAccess.rename_absolute(path+".tmp",path)

func _process(_dt: float) -> bool:
	if busy:return false
	var path:=session_dir.path_join("request.json")
	if not FileAccess.file_exists(path):return false
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:return false
	if not parser.data is Dictionary:return false
	DirAccess.remove_absolute(path);busy=true;execute(parser.data);return false

func inspect() -> Dictionary:
	var flow=root.get_node("AppFlow")
	var result:={"page":flow.page,"loading":flow.loading,"message":flow.message,"bank_cached":ResourceLoader.has_cached(flow.BANK),"bank_nodes":root.find_children("*","Node3D",true,false).size()}
	if current_scene==null:return result
	result.scene=current_scene.name
	var items: Dictionary={}
	if current_scene is Control:
		items=current_scene.controls
		result.discovery=current_scene.browser.rows;result.connection_mode=current_scene.connection_mode
		result.connection_fields=flow.fields
	else:
		var world=current_scene
		result.lighting=world.indirect_stats;result.ui=world.ui.mode;result.hp=world.player_hp
		result.position=[world.player.position.x,world.player.position.y,world.player.position.z]
		var enemies: Array=[]
		for enemy in world.infected:enemies.append({"id":enemy.definition.id,"active":enemy.active,"position":[enemy.position.x,enemy.position.y,enemy.position.z]})
		result.enemies=enemies;result.coop=world.coop.observe();result.started=world.coop.started
		result.server_pid=world.coop.local_server_pid;result.input_enabled=world.coop.input_enabled
		items=world.coop.panel.controls if world.coop.active else world.ui.controls
	result.controls={}
	for id in items:
		var node: Control=items[id];var rect:=node.get_global_rect()
		result.controls[id]={"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"visible":node.is_visible_in_tree(),"disabled":node.disabled if node is BaseButton else false,"text":node.text if node is Label or node is Button or node is LineEdit else ""}
		if node.has_meta("server_id"):result.controls[id].server_id=node.get_meta("server_id")
	return result

func execute(request: Dictionary) -> void:
	var result: Dictionary={}
	match request.command:
		"state":pass
		"click":
			var nodes: Dictionary=current_scene.controls if current_scene is Control else current_scene.coop.panel.controls if current_scene.coop.active else current_scene.ui.controls
			var control: Control=nodes.get(str(request.control))
			if control==null or not control.is_visible_in_tree():result.error="Unavailable control"
			else:
				var point:=control.get_global_rect().get_center()
				for down in [true,false]:
					var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;event.global_position=point;event.set_meta("ai_bridge_input",true);root.push_input(event,true)
		"fields":
			for key in request.values:
				if current_scene.controls.has(key):current_scene.controls[key].text=str(request.values[key])
		"step":
			var frames:=int(request.get("frames",1))
			if frames<1 or frames>600:result.error="out of bounds"
			else:
				for frame in range(frames):
					await physics_frame
					if current_scene!=null and current_scene is Node3D:current_scene.advance(1.0/60.0)
		"act":
			var frames:=clampi(int(request.get("frames",1)),1,600)
			for key_name in request.get("keys",[]):key(key_name,true)
			for frame in range(frames):
				await physics_frame
				if current_scene!=null and current_scene is Node3D:current_scene.advance(1.0/60.0)
			for key_name in request.get("keys",[]):key(key_name,false)
		"capture":
			await RenderingServer.frame_post_draw
			var path:=session_dir.path_join(str(request.get("name","capture"))+".png")
			root.get_texture().get_image().save_png(path);result.capture=path
		"resize":root.size=Vector2i(int(request.width),int(request.height));await process_frame;await process_frame
		"quit":
			if current_scene is Node3D:current_scene.coop.shutdown()
			write_json("response.json",{"id":request.id,"result":{}});quit();return
		_:result.error="unsupported command"
	result.state=inspect();write_json("response.json",{"id":request.id,"result":result});busy=false

func key(value: String,down: bool) -> void:
	var event:=InputEventKey.new();event.keycode=OS.find_keycode_from_string(value);event.physical_keycode=event.keycode;event.pressed=down;event.set_meta("ai_bridge_input",true);root.push_input(event,true)

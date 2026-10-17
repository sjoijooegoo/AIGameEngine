extends SceneTree
## Local debug-only harness: bounded steps, real InputEvents and actual ENet sockets.
## Not copied into release exports. No arbitrary evaluation or network test endpoint.
var session_dir: String
var game: Node3D
var busy := false
var inspection: Camera3D

func _initialize() -> void:
	if not OS.is_debug_build():quit(2);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-session="):session_dir=arg.trim_prefix("--test-session=")
	if session_dir.is_empty() or not DirAccess.dir_exists_absolute(session_dir):quit(2);return
	boot.call_deferred()

func boot() -> void:
	var bank=(load("res://scenes/main.tscn") as PackedScene).instantiate();root.add_child(bank)
	bank.testing=true;game=bank.coop;game.testing=true
	if "--real-time" in OS.get_cmdline_user_args():bank.testing=false;game.testing=true # real physics scheduling, isolated synthetic-input focus
	write_json("ready.json",{"ready":true})

func write_json(filename: String, data: Dictionary) -> void:
	var path:=session_dir.path_join(filename)
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	DirAccess.rename_absolute(path+".tmp",path)

func _process(_dt: float) -> bool:
	if busy or game==null:return false
	var path:=session_dir.path_join("request.json")
	if not FileAccess.file_exists(path):return false
	var text:=FileAccess.get_file_as_string(path)
	if text.is_empty():return false # Windows can briefly deny access just after rename.
	var parser:=JSON.new()
	if parser.parse(text)!=OK:return false
	var value=parser.data
	if not value is Dictionary:return false
	DirAccess.remove_absolute(path)
	busy=true;execute(value);return false

func execute(request: Dictionary) -> void:
	var result: Dictionary={"received_at_ms":Time.get_unix_time_from_system()*1000.0}
	match request.command:
		"step":
			var frames:=int(request.get("frames",1))
			if frames<1 or frames>600:result={"error":"out of bounds"}
			else:
				for frame in range(frames):
					await physics_frame
					game.advance(1.0/60.0)
		"input":
			for key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_E,KEY_R,KEY_1,KEY_2,KEY_3,KEY_4]:
				var event:=InputEventKey.new();event.physical_keycode=key;event.keycode=key;event.pressed=OS.get_keycode_string(key) in request.get("keys",[]);event.set_meta("ai_bridge_input",true);Input.parse_input_event(event)
			if request.has("mouse"):
				var mouse:=InputEventMouseMotion.new();mouse.relative=root.get_final_transform().basis_xform(Vector2(request.mouse[0],request.mouse[1]));mouse.set_meta("ai_bridge_input",true);Input.parse_input_event(mouse)
			for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
				var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=("left" if button==MOUSE_BUTTON_LEFT else "right") in request.get("buttons",[]);event.set_meta("ai_bridge_input",true);Input.parse_input_event(event)
			Input.flush_buffered_events()
		"click":
			var control: Control=game.panel.get(str(request.control))
			var point:=control.get_global_rect().get_center()
			result["control_rect"]=[control.global_position.x,control.global_position.y,control.size.x,control.size.y]
			for down in [true,false]:
				var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=down;mouse.position=point;mouse.global_position=point;mouse.set_meta("ai_bridge_input",true);root.push_input(mouse,true)
		"menu":
			for down in [true,false]:
				var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.physical_keycode=KEY_ESCAPE;event.pressed=down;event.set_meta("ai_bridge_input",true);Input.parse_input_event(event);Input.flush_buffered_events()
		"invalid_input":
			game._confirm_input.rpc_id(1,-1,Vector2(NAN,0),0.0,0.0,false)
		"view":
			# Inspection camera only; does not move players or alter simulation state.
			if inspection==null:inspection=Camera3D.new();game.world.add_child(inspection)
			inspection.position=Vector3(request.position[0],request.position[1],request.position[2])
			inspection.look_at(Vector3(request.target[0],request.target[1],request.target[2]));inspection.current=true
			game.world.held_weapon.hide();game.world.firearms.view.hide()
		"capture":
			await RenderingServer.frame_post_draw
			var path:=session_dir.path_join("capture_%d.png" % int(request.id))
			root.get_texture().get_image().save_png(path);result["capture"]=path
		"fields":
			# Local GUI editing uses the LineEdit model; gameplay still starts by click.
			if request.has("nickname"):game.panel.nickname.text=request.nickname
			if request.has("address"):game.panel.address.text=request.address
			if request.has("port"):game.panel.port.value=request.port
		"fixture":
			if not game.is_host:result={"error":"server fixture only"}
			else:
				game.restore_local();game.world.ensure_infected();game.world.reset_fixture("combat_grab" if request.name=="coop_wipe" else request.name)
				game.round_id+=1
				for context in game.contexts.values():
					context.hp=5 if request.name=="coop_wipe" else 100;context.dead=false;context.hurt_cooldown=0;context.strike_time=-1;context.strike_cooldown=0
					context.feedback.reset();context.weapon.reset("pistol")
					context.body.position=game.original_player.position+Vector3(float(context.body.slot)*1.3,0,0)
					context.body.rotation.y=game.original_player.rotation.y;context.body.aim_pitch=game.world.pitch;context.body.axes=Vector2.ZERO
				game.broadcast_reset()
		"state":pass
		"quit":
			game.disconnect_game();write_json("response.json",{"id":request.id,"result":{}});quit();return
		_:result["error"]="unsupported command"
	result["state"]=game.observe();result.state["input_enabled"]=game.input_enabled
	write_json("response.json",{"id":request.id,"result":result});busy=false

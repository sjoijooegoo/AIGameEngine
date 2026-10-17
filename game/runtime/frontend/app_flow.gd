extends Node
## Application navigation only. The bank is loaded on demand, never preloaded.
const BANK="res://scenes/main.tscn"
const MENU="res://frontend/main.tscn"
var intent: Dictionary={}
var fields: Dictionary={"nickname":"玩家","address":"127.0.0.1","port":24567,"capacity":4}
var page := "home"
var message := ""
var loading := false
var progress := 0.0
var booted := false
var transitioning := false
var bank: Node

func _ready() -> void:
	set_process(false)
	# Test sessions never read or write the real player's preferences.
	if not isolated():
		var cfg:=ConfigFile.new()
		if cfg.load("user://bank_connection.cfg")==OK:
			for key in fields:fields[key]=cfg.get_value("connection",key,fields[key])
	fields.port=clampi(int(fields.port),1024,65535);fields.capacity=clampi(int(fields.capacity),2,4)

func isolated() -> bool:
	for arg in OS.get_cmdline_user_args():
		if OS.is_debug_build() and (arg.begins_with("--ai-session=") or arg.begins_with("--test-session=") or arg=="--performance-benchmark"):return true
	return false

func boot() -> void:
	if booted:return
	booted=true
	var args:=OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--name="):fields.nickname=arg.trim_prefix("--name=")
		if arg.begins_with("--port="):fields.port=arg.trim_prefix("--port=").to_int()
		if arg.begins_with("--connect="):fields.address=arg.trim_prefix("--connect=")
	if "--server" in args or OS.has_feature("dedicated_server"):
		launch({"mode":"server"});return
	for arg in args:
		# Preserve explicit current-bank observation/test entry points.
		if OS.is_debug_build() and (arg.begins_with("--ai-session=") or arg=="--performance-benchmark") and not has_test_session(args):
			launch({"mode":"direct"});return
		if arg.begins_with("--connect="):
			launch({"mode":"multiplayer","action":"cli"});return
	if "--coop" in args:page="multiplayer"

func has_test_session(args: PackedStringArray) -> bool:
	for arg in args:
		if arg.begins_with("--test-session="):return true
	return false

func remember(values: Dictionary) -> void:
	fields=values.duplicate()
	if isolated():return
	var cfg:=ConfigFile.new()
	for key in fields:cfg.set_value("connection",key,fields[key])
	cfg.save("user://bank_connection.cfg")

func launch(options: Dictionary) -> void:
	if loading or transitioning:return
	intent=options.duplicate();message="";loading=true;progress=0;page="loading"
	# Start in the next frame so the loading screen is painted first.
	begin_load.call_deferred()

func begin_load() -> void:
	await get_tree().process_frame
	var error:=ResourceLoader.load_threaded_request(BANK)
	if error!=OK:
		loading=false;page="home";message="银行资源无法读取，请检查安装文件。";return
	set_process(true)

func _process(_dt: float) -> void:
	var values: Array=[]
	var status:=ResourceLoader.load_threaded_get_status(BANK,values)
	if not values.is_empty():progress=float(values[0])
	if status==ResourceLoader.THREAD_LOAD_FAILED or status==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		loading=false;page="home";message="银行资源加载失败，请检查安装文件。";set_process(false)
	elif status==ResourceLoader.THREAD_LOAD_LOADED:
		set_process(false)
		# Getting the ready resource doesn't wait for worker I/O.
		var scene=ResourceLoader.load_threaded_get(BANK)
		await get_tree().process_frame
		var error:=get_tree().change_scene_to_packed(scene)
		if error!=OK:loading=false;page="home";message="银行场景无法打开。"

func bank_ready(world: Node) -> void:
	bank=world;loading=false
	if intent.get("mode")=="single":
		world.ensure_infected()
	elif intent.get("mode")=="multiplayer":
		world.coop.open_menu()
		world.coop.panel.nickname.text=fields.nickname
		world.coop.panel.address.text=fields.address;world.coop.panel.port.value=fields.port
		if intent.get("action")=="create":world.coop.create_session(int(fields.port),int(fields.capacity),fields.nickname)
		elif intent.get("action")=="join":
			if world.coop.join_game(fields.address,int(fields.port),fields.nickname)!=OK:return_menu("multiplayer","无法创建连接，请检查地址和端口。")
	print("BANK_ENTRY_READY ",intent.get("mode","direct"))

func return_menu(next_page: String="home",reason: String="") -> void:
	if transitioning:return
	transitioning=true
	finish_return.call_deferred(next_page,reason)

func finish_return(next_page: String,reason: String) -> void:
	if is_instance_valid(bank) and bank.coop!=null:bank.coop.shutdown()
	bank=null;intent={};page=next_page;message=reason;loading=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU)
	await get_tree().process_frame
	transitioning=false

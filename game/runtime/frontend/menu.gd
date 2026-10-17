extends Control
## Lightweight title and connection forms. No bank scenes or actors are preloaded.
const S=preload("res://ui/style.gd")
var controls: Dictionary={}
var content: Control
var current_page := ""
var connection_mode := "find"
var browser: Node
var selected_server := "localhost:24567"
var server_rows: VBoxContainer
var settings: Dictionary={"volume":.8,"sensitivity":1.0,"large_text":false}

func _ready() -> void:
	S.fonts();theme=S.theme_for(1.0)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var background:=ColorRect.new();background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var material:=ShaderMaterial.new();material.shader=preload("res://frontend/background.gdshader");background.material=material
	background.mouse_filter=MOUSE_FILTER_IGNORE;add_child(background)
	content=Control.new();content.set_anchors_and_offsets_preset(PRESET_FULL_RECT);content.mouse_filter=MOUSE_FILTER_IGNORE;add_child(content)
	browser=preload("res://coop/discovery.gd").new();add_child(browser);browser.browse()
	browser.add_target(str(AppFlow.fields.address),int(AppFlow.fields.port));browser.changed.connect(refresh_servers)
	if not AppFlow.isolated():
		var cfg:=ConfigFile.new()
		if cfg.load("user://bank_ui_settings.cfg")==OK:
			for key in settings:settings[key]=cfg.get_value("ui",key,settings[key])
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(settings.volume))))
	resized.connect(rebuild)
	AppFlow.boot();rebuild()
	print("BANK_MAIN_MENU bank_loaded=false")

func _process(_dt: float) -> void:
	browser.active=current_page=="multiplayer" and connection_mode=="find"
	if current_page!=AppFlow.page:rebuild()
	if current_page=="loading" and controls.has("loading_progress"):
		controls.loading_progress.text="资源读取  %03d %%\n正在准备建筑、光照与角色…" % roundi(AppFlow.progress*100)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if current_page in ["settings","help","multiplayer"]:navigate("home");get_viewport().set_input_as_handled()

func navigate(next: String) -> void:
	if current_page=="multiplayer":remember_form()
	AppFlow.page=next;AppFlow.message="";rebuild()

func label(id: String,text: String,rect: Rect2,font_size: int=18,color: Color=S.PAPER,font: Font=null) -> Label:
	var node:=Label.new();node.name=id;node.text=text;node.position=rect.position;node.size=rect.size
	var scale: float=maxf(.45,get_viewport().get_final_transform().get_scale().x)
	node.add_theme_font_size_override("font_size",maxi(font_size,ceili(12.0/scale)));node.add_theme_color_override("font_color",color)
	if font:node.add_theme_font_override("font",font)
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.mouse_filter=MOUSE_FILTER_IGNORE
	content.add_child(node);controls[id]=node;return node

func button(id: String,text: String,rect: Rect2,callback: Callable) -> Button:
	var node:=Button.new();node.name=id;node.text=text;node.position=rect.position;node.size=rect.size
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT;node.mouse_default_cursor_shape=CURSOR_POINTING_HAND
	node.pressed.connect(callback);content.add_child(node);controls[id]=node;return node

func line(at: Vector2,width: float,color: Color=S.LINE) -> void:
	var node:=ColorRect.new();node.position=at;node.size=Vector2(width,1);node.color=color;node.mouse_filter=MOUSE_FILTER_IGNORE;content.add_child(node)

func input(id: String,value: String,rect: Rect2,placeholder: String,max_length: int) -> LineEdit:
	var node:=LineEdit.new();node.name=id;node.text=value;node.placeholder_text=placeholder;node.max_length=max_length
	node.position=rect.position;node.size=rect.size
	node.add_theme_stylebox_override("normal",S.box(Color("0e1815"),S.LINE))
	node.add_theme_stylebox_override("focus",S.box(Color("15221c"),S.BRASS,2))
	node.add_theme_color_override("font_color",S.PAPER);content.add_child(node);controls[id]=node;return node

func rebuild() -> void:
	if content==null or size.x<20:return
	for child in content.get_children():content.remove_child(child);child.queue_free()
	controls.clear();current_page=AppFlow.page
	var scale: float=maxf(.45,get_viewport().get_final_transform().get_scale().x)
	theme=S.theme_for(maxf(1.0,14.0/(18.0*scale)))
	var w:=size.x;var h:=size.y
	label("eyebrow","封锁区域  /  RESTRICTED AREA",Rect2(60,36,w-120,28),13,S.BRASS,S.mono)
	line(Vector2(60,h-48),w-120)
	label("footer","BANK CRISIS   /   隔离区域",Rect2(60,h-40,w*.5,30),12,S.MUTED,S.mono)
	var hint:=label("hint","方向键选择  ·  回车确认",Rect2(w-350,h-40,290,30),12,S.MUTED);hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	match current_page:
		"home":build_home(w,h)
		"multiplayer":build_connection(w,h)
		"settings":build_settings(w,h)
		"help":build_help(w,h)
		"loading":
			label("title","正在进入银行",Rect2(60,150,w-120,75),46,S.PAPER,S.title)
			label("loading_progress","准备资源…",Rect2(64,270,w*.65,110),22,S.BRASS,S.mono)
			label("loading_note","首次进入需要准备角色与光照，请稍候。",Rect2(64,410,w*.65,60),16,S.MUTED)
	if not AppFlow.message.is_empty() and current_page!="multiplayer":label("error",AppFlow.message,Rect2(w*.57,h-160,w*.36,70),16,S.DANGER)
	for node in controls.values():
		if node is Button and not node.disabled:node.call_deferred("grab_focus");break

func build_home(w: float,h: float) -> void:
	label("title","银行危机",Rect2(54,h*.16,w*.55,100),72,S.PAPER,S.title)
	label("subtitle","B A N K   C R I S I S",Rect2(60,h*.16+105,w*.5,42),18,S.MUTED,S.mono)
	var y: float=maxf(h*.43,300);var width: float=minf(420,w*.42)
	button("single","01    单人模式",Rect2(60,y,width,46),func():AppFlow.launch({"mode":"single"}))
	button("multiplayer","02    多人模式",Rect2(60,y+56,width,46),func():navigate("multiplayer"))
	button("settings","03    行动设置",Rect2(60,y+112,width,46),func():navigate("settings"))
	button("help","04    操作手册",Rect2(60,y+168,width,46),func():navigate("help"))
	button("quit","05    退出游戏",Rect2(60,y+224,width,46),func():get_tree().quit())
	var x: float=w*.60
	label("building_label","建筑档案  /  04 FLOORS",Rect2(x,h*.36-38,w*.33,30),13,S.BRASS,S.mono)
	var plate=preload("res://ui/equipment_plate.gd").new();plate.building=true;plate.position=Vector2(x,h*.36);plate.size=Vector2(w*.33,h*.32);content.add_child(plate)
	label("note","独自探索，或与队友并肩进入。",Rect2(x,h*.73,w*.33,42),20,S.PAPER,S.title)
	label("note_detail","单人探索  /  最多 4 人随时加入",Rect2(x,h*.73+50,w*.33,40),14,S.MUTED)

func build_connection(w: float,h: float) -> void:
	label("title","多人合作",Rect2(58,82,w-116,64),42,S.PAPER,S.title)
	label("steps","寻找服务器  /  连接成功即进入银行  /  最多 4 人",Rect2(60,152,w-120,35),15,S.BRASS)
	var width: float=minf(520,w*.47);var right: float=w*.60
	for i in 3:
		var key: String=["find","join","create"][i]
		button(key+"_tab",["寻找服务器","直接连接","创建本地会话"][i],Rect2(60+i*(width+8)/3,210,(width-16)/3,44),func():remember_form();connection_mode=key;AppFlow.message="";rebuild())
	controls[connection_mode+"_tab"].add_theme_stylebox_override("normal",S.box(Color("2e3930"),S.BRASS))
	label("name_label","你的呼号",Rect2(60,272,width,26),14,S.MUTED)
	input("nickname",str(AppFlow.fields.nickname),Rect2(60,304,width,44),"输入队友能辨认的名字",24)
	label("host_label","服务器地址" if connection_mode=="join" else "会话人数" if connection_mode=="create" else "可用服务器 · 每 2 秒自动检测",Rect2(60,366,width,26),14,S.MUTED)
	if connection_mode=="find":
		var scroll:=ScrollContainer.new();scroll.position=Vector2(60,398);scroll.size=Vector2(width,144);content.add_child(scroll)
		server_rows=VBoxContainer.new();server_rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(server_rows)
	elif connection_mode=="join":
		input("address",str(AppFlow.fields.address),Rect2(60,398,width,44),"IP 或域名，例如 127.0.0.1",253)
	else:
		var select:=OptionButton.new();select.position=Vector2(60,398);select.size=Vector2(width,44)
		for count in [2,3,4]:select.add_item("%d 人合作会话" % count,count)
		select.select(int(AppFlow.fields.capacity)-2);content.add_child(select);controls.capacity=select
	if connection_mode!="find":
		label("port_label","UDP 端口",Rect2(60,460,130,30),14,S.MUTED)
		input("port",str(AppFlow.fields.port),Rect2(210,456,width-150,44),"24567",5)
	label("error",AppFlow.message,Rect2(60,544 if connection_mode=="find" else 510,width,28 if connection_mode=="find" else 48),14,S.DANGER)
	button("connect","创建并进入会话" if connection_mode=="create" else "连接服务器",Rect2(60,h-144,width,48),submit)
	button("back","返回主菜单",Rect2(right,h-144,w*.33,48),func():navigate("home"))
	line(Vector2(right,218),w*.33,S.BRASS)
	label("brief_title","随时加入，并肩作战。",Rect2(right,244,w*.33,45),26,S.PAPER,S.title)
	label("brief","连接成功就进入银行，无需等待队友。\n人数实时显示，达到上限后停止接纳。\n\n寻找本机、局域网与最近的服务器。\n公网 VPS 可使用「直接连接」。",Rect2(right,302,w*.33,148),16,S.MUTED)
	if connection_mode=="find":button("refresh","刷新服务器",Rect2(right,462,w*.33,42),func():browser.refresh())
	label("server_note","localhost 指向本机常驻服务。\n创建本地会话则随创建者离开而关闭。",Rect2(right,h-210,w*.33,52),13,S.BRASS)
	if connection_mode=="find":refresh_servers();browser.refresh.call_deferred()

func refresh_servers() -> void:
	if current_page!="multiplayer" or connection_mode!="find" or not is_instance_valid(server_rows):return
	for child in server_rows.get_children():server_rows.remove_child(child);child.queue_free()
	for key in controls.keys():
		if str(key).begins_with("server_") and key!="server_note":controls.erase(key)
	var i:=0
	for id in browser.rows:
		var row: Dictionary=browser.rows[id]
		var status: String=("%d/%d 人 · %d ms" % [row.players,row.capacity,row.ping]) if row.online else "未连接 · 服务未响应"
		if row.online and not row.compatible:status="服务器版本不匹配"
		var node:=Button.new();node.name="server_"+str(i);node.text="%s  %s  ·  %s" % ["●" if row.online else "○",row.address+":"+str(row.port),status]
		node.set_meta("server_id",id)
		node.tooltip_text=row.name;node.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		node.alignment=HORIZONTAL_ALIGNMENT_LEFT;node.custom_minimum_size.y=48;node.add_theme_font_size_override("font_size",maxi(16,ceili(12.0/maxf(.45,get_viewport().get_final_transform().get_scale().x))))
		node.pressed.connect(func():selected_server=id;refresh_servers());server_rows.add_child(node);controls[node.name]=node
		if id==selected_server:node.add_theme_stylebox_override("normal",S.box(Color("2e3930"),S.BRASS))
		i+=1
	var selected: Dictionary=browser.rows.get(selected_server,{})
	if controls.has("connect"):
		var full: bool=int(selected.get("players",0))>=int(selected.get("capacity",4))
		controls.connect.disabled=not selected.get("online",false) or not selected.get("compatible",false) or full
		controls.connect.text="服务器已满（%d/%d）" % [selected.players,selected.capacity] if full else "加入选中服务器"

func remember_form() -> void:
	var values: Dictionary=AppFlow.fields.duplicate()
	for key in ["nickname","address"]:
		if controls.has(key):values[key]=controls[key].text.strip_edges()
	if controls.has("port") and controls.port.text.is_valid_int():values.port=controls.port.text.to_int()
	if controls.has("capacity"):values.capacity=controls.capacity.get_selected_id()
	AppFlow.remember(values)
	browser.add_target(str(values.address),int(values.port))

func submit() -> void:
	if AppFlow.loading:return
	var error:=""
	if controls.nickname.text.strip_edges().is_empty():error="请先填写你的呼号。"
	elif connection_mode!="find" and (not controls.port.text.is_valid_int() or controls.port.text.to_int()<1024 or controls.port.text.to_int()>65535):error="端口请输入 1024–65535 之间的整数。"
	elif connection_mode=="join":
		var host: String=controls.address.text.strip_edges();var valid:=RegEx.new();valid.compile("^[A-Za-z0-9._:-]+$")
		if host.is_empty() or valid.search(host)==null:error="请填写服务器 IP 或域名，不需要 http:// 或端口。"
	if not error.is_empty():
		AppFlow.message=error;controls.error.text=error;return
	remember_form()
	if connection_mode=="find":
		var row: Dictionary=browser.rows.get(selected_server,{})
		if not row.get("online",false) or int(row.players)>=int(row.capacity):return
		AppFlow.fields.address=row.address;AppFlow.fields.port=row.port;AppFlow.remember(AppFlow.fields)
	AppFlow.launch({"mode":"multiplayer","action":"join" if connection_mode=="find" else connection_mode})

func build_settings(w: float,h: float) -> void:
	label("title","行动设置",Rect2(58,92,w-116,64),42,S.PAPER,S.title)
	for i in range(3):
		var y:=230+i*106
		label("setting_"+str(i),["总音量","鼠标灵敏度","界面文字"][i],Rect2(60,y,w*.43,50),22)
		if i<2:
			var key: String="volume" if i==0 else "sensitivity"
			button(key+"_less","−",Rect2(w*.59,y,64,48),func():change_setting(key,-.1))
			label(key+"_value",str(roundi(settings.volume*100))+" %" if i==0 else "%.1f ×"%settings.sensitivity,Rect2(w*.59+86,y+5,125,45),24,S.BRASS)
			button(key+"_more","+",Rect2(w*.59+230,y,64,48),func():change_setting(key,.1))
		else:button("large_text","放大游戏界面" if settings.large_text else "标准游戏界面",Rect2(w*.59,y,294,48),func():change_setting("large_text",0))
	button("back","返回主菜单",Rect2(60,h-144,300,48),func():navigate("home"))
	label("note","设置自动保存在本机，进入游戏后生效。",Rect2(w*.47,h-144,w*.46,48),16,S.MUTED)

func change_setting(key: String,amount: float) -> void:
	if key=="large_text":settings[key]=not settings[key]
	else:settings[key]=snappedf(clampf(float(settings[key])+amount,0 if key=="volume" else .4,1 if key=="volume" else 2),.1)
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(settings.volume))))
	if not AppFlow.isolated():
		var cfg:=ConfigFile.new()
		for setting in settings:cfg.set_value("ui",setting,settings[setting])
		cfg.save("user://bank_ui_settings.cfg")
	rebuild()

func build_help(w: float,h: float) -> void:
	label("title","操作手册",Rect2(58,92,w-116,64),42,S.PAPER,S.title)
	var pairs: Array=[["W A S D","移动"],["SHIFT","奔跑"],["鼠标左键 / 右键","攻击 / 推开"],["R","装填弹药"],["1 / 2 / 3 / 4","切换装备"],["E / F","开关门 / 手电"],["TAB","单人随身装备"],["ESC","暂停单人 / 多人会话"]]
	for i in pairs.size():
		label("key_"+str(i),pairs[i][0],Rect2(60,200+i*40,w*.32,36),21,S.BRASS,S.mono)
		label("action_"+str(i),pairs[i][1],Rect2(w*.40,200+i*40,w*.5,36),21)
	label("help_note","被抓住时，交替按 A / D 挣脱。多人会话菜单不会暂停战斗。",Rect2(60,532,w-120,30),14,S.MUTED)
	button("back","返回主菜单",Rect2(60,h-144,300,48),func():navigate("home"))

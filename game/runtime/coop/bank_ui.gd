extends Control
const S=preload("res://ui/style.gd")
var game: Node3D
var address: LineEdit
var port: SpinBox
var nickname: LineEdit
var capacity: OptionButton
var menu: PanelContainer
var status_label: Label
var members: Label
var join_button: Button
var create_button: Button
var leave_button: Button
var resume_button: Button
var back_button: Button
var restart_button: Button
var controls: Dictionary={}
var connection_fields: VBoxContainer
var team_hud: Label
var lobby_backdrop: ColorRect
var lobby_header: Label
var endpoint_label: Label

func _ready() -> void:
	S.fonts();theme=S.theme_for(1.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	lobby_backdrop=ColorRect.new();lobby_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);lobby_backdrop.color=Color("09100e");add_child(lobby_backdrop)
	var backdrop_material:=ShaderMaterial.new();backdrop_material.shader=preload("res://frontend/background.gdshader");lobby_backdrop.material=backdrop_material
	lobby_header=Label.new();lobby_header.text="BANK CRISIS   /   正在进入服务器";lobby_header.position=Vector2(60,36);lobby_header.add_theme_color_override("font_color",S.BRASS);lobby_header.add_theme_font_size_override("font_size",14);add_child(lobby_header)
	team_hud=Label.new();team_hud.position=Vector2(20,155);team_hud.add_theme_font_size_override("font_size",16);add_child(team_hud)
	menu=PanelContainer.new();menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER);menu.position=Vector2(-280,-300);menu.custom_minimum_size=Vector2(560,600);add_child(menu)
	var background:=StyleBoxFlat.new();background.bg_color=Color("101b20f5");background.border_color=S.BRASS
	background.set_border_width_all(1);background.set_content_margin_all(24);menu.add_theme_stylebox_override("panel",background)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);menu.add_child(box)
	var tag:=Label.new();tag.text="BANK CRISIS  /  COOPERATIVE OPERATION";tag.add_theme_color_override("font_color",S.BRASS);tag.add_theme_font_size_override("font_size",14);box.add_child(tag)
	var title:=Label.new();title.text="多人合作会话";title.add_theme_font_size_override("font_size",30);box.add_child(title)
	status_label=Label.new();status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status_label)
	endpoint_label=Label.new();endpoint_label.add_theme_font_size_override("font_size",14);endpoint_label.add_theme_color_override("font_color",S.BRASS);box.add_child(endpoint_label)
	connection_fields=VBoxContainer.new();connection_fields.add_theme_constant_override("separation",9);box.add_child(connection_fields)
	nickname=LineEdit.new();nickname.text="玩家";nickname.placeholder_text="你的呼号";nickname.max_length=24;connection_fields.add_child(nickname);controls.nickname=nickname
	address=LineEdit.new();address.text="127.0.0.1";address.placeholder_text="服务器 IP 或域名";connection_fields.add_child(address);controls.address=address
	var row:=HBoxContainer.new();connection_fields.add_child(row)
	var label:=Label.new();label.text="UDP 端口  ";row.add_child(label)
	port=SpinBox.new();port.min_value=1024;port.max_value=65535;port.value=24567;port.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(port)
	capacity=OptionButton.new();capacity.add_item("2 人会话",2);capacity.add_item("3 人会话",3);capacity.add_item("4 人会话",4);capacity.select(2);row.add_child(capacity)
	create_button=button(box,"create_button","创建本地会话",func():game.create_session(int(port.value),capacity.get_selected_id(),nickname.text))
	join_button=button(box,"join_button","加入指定服务器",func():game.join_game(address.text,int(port.value),nickname.text))
	members=Label.new();members.add_theme_font_size_override("font_size",16);box.add_child(members)
	resume_button=button(box,"resume_button","继续行动",func():game.resume())
	restart_button=button(box,"restart_button","全队重新开始",func():game.send_action("restart",true))
	leave_button=button(box,"leave_button","离开会话",func():game.leave_session())
	back_button=button(box,"back_button","返回单人模式",func():game.back_to_solo())
	var hint:=Label.new();hint.text="WASD 移动 · Shift 奔跑 · E 开门 · 1–4 装备\n左键攻击 · 右键推开 · R 装填 · Esc 会话\n菜单不会暂停战斗。创建者退出会关闭本地服务端。";hint.add_theme_font_size_override("font_size",14);hint.add_theme_color_override("font_color",S.MUTED);box.add_child(hint)
	game.status_changed.connect(refresh);refresh()

func button(parent: Node, id: String, text: String, action: Callable) -> Button:
	var node:=Button.new();node.name=id;node.text=text;node.custom_minimum_size.y=40;node.pressed.connect(action);parent.add_child(node);controls[id]=node;return node

func refresh() -> void:
	visible=game.active;menu.visible=not game.input_enabled
	lobby_backdrop.visible=game.frontend_managed and not game.started
	lobby_header.visible=lobby_backdrop.visible
	status_label.text="正在同步银行场景…" if game.players.has(game.local_id) and not game.started else game.status
	var connected: bool=game.players.has(game.local_id)
	endpoint_label.visible=connected and not game.started
	endpoint_label.text="%s : %d   /   %d/%d 人" % [address.text,int(port.value),game.players.size(),game.max_players]
	if game.frontend_managed:
		var height: float=440 if connected else 340
		menu.custom_minimum_size=Vector2(560,height);menu.size=Vector2(560,height)
		menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER,Control.PRESET_MODE_KEEP_SIZE)
	connection_fields.visible=not connected and not game.frontend_managed
	create_button.visible=connection_fields.visible;join_button.visible=connection_fields.visible
	create_button.disabled=game.peer!=null or game.launching;join_button.disabled=create_button.disabled
	resume_button.visible=connected and game.started;leave_button.visible=game.peer!=null or game.launching
	back_button.visible=not connected
	back_button.text="取消并返回连接页面" if game.frontend_managed else "返回单人模式"
	if game.frontend_managed:leave_button.visible=connected
	refresh_hud()

func refresh_hud() -> void:
	var lines:=PackedStringArray()
	for id in game.players:
		var body=game.players[id];var state: Dictionary=game.team.get(id,{})
		lines.append("%s%s  ·  %s" % [body.display_name,"（你）" if id==game.local_id else "", "阵亡" if state.get("dead",false) else "生命 %d" % int(state.get("hp",100))])
	members.text="\n".join(lines);team_hud.text="合作 %d/%d  ·  击倒 %d\n" % [game.players.size(),game.max_players,game.world.kills]+"\n".join(lines)
	team_hud.visible=game.input_enabled
	if game.team_wiped:team_hud.text+="\n全队阵亡 · Esc 打开会话后重新开始"
	elif game.world.player_dead:team_hud.text+="\n你已阵亡 · 等待队友，Esc 可离开会话"
	var state: Dictionary=game.team.get(game.local_id,{})
	if state.get("grabbed",false):team_hud.text+="\n被抓住：交替 A / D 挣脱，或等待队友救援"
	restart_button.visible=game.team_wiped

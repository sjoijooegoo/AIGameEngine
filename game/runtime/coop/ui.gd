extends Control
var game: Node3D
var address: LineEdit
var port: SpinBox
var nickname: LineEdit
var menu: PanelContainer
var status_label: Label
var members: Label
var join_button: Button
var leave_button: Button
var resume_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	var hud:=VBoxContainer.new();hud.position=Vector2(22,18);add_child(hud)
	status_label=Label.new();status_label.add_theme_font_size_override("font_size",20);hud.add_child(status_label)
	members=Label.new();hud.add_child(members)
	menu=PanelContainer.new();menu.position=Vector2(35,125);menu.custom_minimum_size=Vector2(370,0);add_child(menu)
	var margin:=MarginContainer.new()
	for edge in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+edge,20)
	menu.add_child(margin)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);margin.add_child(box)
	var title:=Label.new();title.text="银行合作 · 联机预览";title.add_theme_font_size_override("font_size",26);box.add_child(title)
	var hint:=Label.new();hint.text="本轮：2–4 人移动与角色同步\nWASD 移动 · Shift 奔跑 · Esc 菜单\n战斗、开门与任务尚未接入联机";box.add_child(hint)
	nickname=LineEdit.new();nickname.text="玩家";nickname.placeholder_text="玩家名称";nickname.max_length=24;box.add_child(nickname)
	address=LineEdit.new();address.text="127.0.0.1";address.placeholder_text="服务器 IP / 域名";box.add_child(address)
	port=SpinBox.new();port.min_value=1024;port.max_value=65535;port.value=24567;box.add_child(port)
	join_button=Button.new();join_button.text="加入服务器";join_button.pressed.connect(func():
		var error: int=game.join_game(address.text,int(port.value),nickname.text)
		if error!=OK:game.set_status("请检查地址和端口"))
	box.add_child(join_button)
	resume_button=Button.new();resume_button.text="继续游戏";resume_button.pressed.connect(func():game.input_enabled=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;refresh());box.add_child(resume_button)
	leave_button=Button.new();leave_button.text="退出房间";leave_button.pressed.connect(func():game.disconnect_game());box.add_child(leave_button)
	game.status_changed.connect(refresh);refresh()

func refresh() -> void:
	status_label.text=game.status
	var names:=PackedStringArray()
	for body in game.players.values():names.append("%d  %s%s" % [body.slot+1,body.display_name,"（你）" if body.peer_id==game.local_id else ""])
	members.text="\n".join(names)
	var connected: bool=game.players.has(game.local_id)
	menu.visible=not game.input_enabled
	join_button.visible=not connected;resume_button.visible=connected;leave_button.visible=game.peer!=null
	address.visible=not connected;port.visible=not connected;nickname.visible=not connected

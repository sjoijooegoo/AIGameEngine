extends CanvasLayer
## Single input/modal owner. Views bind game state; controls call ordinary
## weapon/settings actions. Pausing never pauses the test bridge or UI tree.
const S=preload("res://ui/style.gd")
const LABELS={"pistol":"半自动手枪","shotgun":"泵动霰弹枪","torch":"手电筒","baton":"警棍"}
const DESCRIPTIONS={"pistol":"稳定的单发射击。\n瞄准头部，在每一发之间留出恢复准星的时间。","shotgun":"近距离压制，多弹丸散射。\n逐发装填；留意弹仓余量与泵动间隔。","torch":"照亮走廊、门口和阴影。\nF 开关光源，右键可推开靠近的感染者。","baton":"连续三段近战，末段重击。\n按住左键连续攻击，右键推开；注意攻击距离。"}
var world: Node3D
var root: Control
var page: Control
var veil: ColorRect
var backdrop_copy: BackBufferCopy
var hud: Control
var mode:="play"
var return_mode:="pause"
var selected_item:="pistol"
var has_run:=false
var controls: Dictionary={}
var font_factor:=1.0
var clock:=0.0
var settings:={"volume":.8,"sensitivity":1.0,"large_text":false}
var menu_camera: Camera3D
var badge: Texture2D=preload("res://ui/icons/bank.svg")
var pending_confirm:=""
var rebuilding:=false
var last_health:=100.0

func setup(game: Node3D) -> void:
	world=game;layer=20;S.fonts()
	if not world.testing:
		var cfg:=ConfigFile.new()
		if cfg.load("user://bank_ui_settings.cfg")==OK:
			settings.volume=clampf(float(cfg.get_value("ui","volume",.8)),0,1)
			settings.sensitivity=clampf(float(cfg.get_value("ui","sensitivity",1)),.4,2)
			settings.large_text=bool(cfg.get_value("ui","large_text",false))
	apply_settings(false)
	root=Control.new();root.name="BankUI";root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(root)
	hud=preload("res://ui/hud.gd").new();hud.shell=self;hud.world=world;root.add_child(hud)
	backdrop_copy=BackBufferCopy.new();backdrop_copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;root.add_child(backdrop_copy);backdrop_copy.hide()
	veil=ColorRect.new();veil.name="MenuVeil";veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);veil.mouse_filter=Control.MOUSE_FILTER_STOP
	var material:=ShaderMaterial.new();material.shader=preload("res://ui/menu_veil.gdshader");veil.material=material;root.add_child(veil);veil.hide()
	page=Control.new();page.name="Page";page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);page.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(page)
	menu_camera=Camera3D.new();menu_camera.name="MenuCamera";world.add_child(menu_camera)
	menu_camera.position=Vector3(10,1.85,20);menu_camera.look_at(Vector3(25,1.35,5));menu_camera.fov=70;menu_camera.current=false
	root.resized.connect(rebuild)
	rebuild()

func apply_settings(save: bool=true) -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(settings.volume))))
	if save and not world.testing:
		var cfg:=ConfigFile.new()
		for key in settings:cfg.set_value("ui",key,settings[key])
		cfg.save("user://bank_ui_settings.cfg")

func change_setting(key: String,amount: float) -> void:
	if key=="large_text":settings.large_text=not settings.large_text
	else:settings[key]=snappedf(clampf(float(settings[key])+amount,0 if key=="volume" else .4,1 if key=="volume" else 2),.1)
	apply_settings();rebuild()

func blocks_world() -> bool:return mode in ["title","pause","loadout","settings","help","confirm"]

func set_mode(next: String) -> void:
	if mode==next:return
	mode=next;world.held_actions.clear();world.firearms.clear_input();world.strike_time=-1
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if mode=="play" else Input.MOUSE_MODE_VISIBLE
	# Freeze ongoing world voices; clear_input separately cancels queued actions.
	for type in ["AudioStreamPlayer","AudioStreamPlayer3D"]:
		for player in world.find_children("*",type,true,false):player.stream_paused=blocks_world()
	var title_background: bool=mode=="title" or (mode in ["settings","help","confirm"] and return_mode=="title")
	menu_camera.current=title_background
	if not title_background:world.camera.current=true
	if world.camera_motion.ready:world.camera_motion.reset()
	world.update_indoor_lights()
	world.held_weapon.visible=mode=="play" and world.firearms.selected=="torch" and not world.player_dead
	world.firearms.view.visible=mode=="play" and world.firearms.selected!="torch" and not world.player_dead
	world.firearms.hud.visible=mode=="play" and not world.player_dead
	rebuild()

func reset_play() -> void:
	clock=0;has_run=true;last_health=100
	if hud: hud.health_display=100;hud.previous_weapon="";hud.switch_time=0
	set_mode("play")

func begin_game() -> void:
	world.reset_fixture("default");has_run=true;set_mode("play")

func title_screen() -> void:set_mode("title")

func close_page() -> void:
	set_mode(return_mode if mode in ["settings","help"] else "play" if mode in ["pause","loadout"] else "pause" if mode=="confirm" else mode)

func open_page(next: String) -> void:
	return_mode=mode;set_mode(next)

func confirm(action: String) -> void:
	pending_confirm=action;return_mode=mode;set_mode("confirm")

func confirm_action() -> void:
	if pending_confirm=="restart":begin_game()
	elif pending_confirm=="quit":world.get_tree().quit()

func handle_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if code==KEY_ESCAPE:
			if mode=="play":set_mode("pause")
			elif mode=="confirm":set_mode(return_mode)
			elif mode!="title" and mode!="dead":close_page()
			world.get_viewport().set_input_as_handled();return true
		if code==KEY_TAB and mode in ["play","loadout"]:
			if mode=="play" and world.feedback.is_grabbed():return true
			selected_item=world.firearms.selected;set_mode("loadout" if mode=="play" else "play")
			world.get_viewport().set_input_as_handled();return true
		if mode=="dead" and code==KEY_R:
			begin_game();world.get_viewport().set_input_as_handled();return true
	return mode!="play"

func advance(dt: float) -> void:
	clock+=dt
	if world.player_dead and mode=="play":set_mode("dead")
	hud.advance(dt)

func floor_code() -> String:return "%dF"%(clampi(floori((world.player.position.y+.4)/3.6),0,3)+1)

func location_name() -> String:
	var floor_index:=clampi(floori((world.player.position.y+.4)/3.6),0,3)
	var level: Dictionary=world.spec.levels[floor_index];var closest:="银行内部";var distance:=INF
	for place in level.labels:
		var delta:=Vector2(float(place.x)-world.player.position.x,float(place.z)-world.player.position.z).length_squared()
		if delta<distance:closest=place.text;distance=delta
	return closest

func label(id: String,value: String,rect: Rect2,font_size:=18,color: Color=S.PAPER,font: Font=null,wrap:=false) -> Label:
	var node:=Label.new();node.name=id;node.text=value;node.position=rect.position;node.size=rect.size
	node.add_theme_font_size_override("font_size",roundi(font_size*font_factor));node.add_theme_color_override("font_color",color)
	if font:node.add_theme_font_override("font",font)
	if wrap:node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(node);controls[id]=node
	return node

func button(id: String,value: String,rect: Rect2,callback: Callable) -> Button:
	var node:=Button.new();node.name=id;node.text=value;node.position=rect.position;node.size=rect.size;node.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT;node.pressed.connect(callback);page.add_child(node);controls[id]=node
	return node

func rule(at: Vector2,width: float,color: Color=S.LINE) -> void:
	var node:=ColorRect.new();node.color=color;node.position=at;node.size=Vector2(width,1);node.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(node)

func panel(rect: Rect2) -> void:
	var node:=Panel.new();node.position=rect.position;node.size=rect.size;node.add_theme_stylebox_override("panel",S.box(Color(.04,.065,.055,.88),S.LINE));node.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(node)

func plate(rect: Rect2,key: String="",building: bool=false) -> void:
	var node=preload("res://ui/equipment_plate.gd").new();node.position=rect.position;node.size=rect.size;node.weapon=key;node.building=building;page.add_child(node)

func content_top() -> float:return maxf(200,98+95*font_factor)
func back_y(height: float=48) -> float:return root.size.y-62-height*font_factor

func header(english: String,chinese: String,sub: String="") -> void:
	var w:=root.size.x
	label("eyebrow",english,Rect2(56,34,w-112,24*font_factor),13,S.BRASS,S.mono)
	label("heading",chinese,Rect2(54,60+12*font_factor,w-108,56*font_factor),38,S.PAPER,S.title)
	if not sub.is_empty():label("subheading",sub,Rect2(56,70+68*font_factor,w-112,30*font_factor),15,S.MUTED)

func rebuild() -> void:
	if rebuilding or root==null or page==null:return
	rebuilding=true
	var prior_focus: String=""
	var focused: Control=get_viewport().gui_get_focus_owner()
	if focused!=null:prior_focus=str(focused.name)
	for child in page.get_children():page.remove_child(child);child.queue_free()
	controls.clear()
	var scale_x: float=get_viewport().get_final_transform().get_scale().x
	font_factor=maxf(1,1/maxf(scale_x,.45))*(1.15 if settings.large_text else 1.0)
	root.theme=S.theme_for(font_factor)
	veil.visible=mode!="play";page.visible=mode!="play";hud.visible=mode=="play"
	backdrop_copy.visible=mode!="play"
	veil.material.set_shader_parameter("title_screen",1.0 if mode=="title" else 0.0)
	var w:=root.size.x;var h:=root.size.y
	if w<10 or h<10:rebuilding=false;return
	match mode:
		"title":build_title(w,h)
		"pause":build_pause(w,h)
		"settings":build_settings(w,h)
		"loadout":build_loadout(w,h)
		"help":build_help(w,h)
		"dead":build_death(w,h)
		"confirm":build_confirm(w,h)
	if mode!="play":
		rule(Vector2(56,h-43),w-112)
		label("footer","BANK CRISIS  /  隔离区域",Rect2(56,h-36,w*.45-56,30),12,S.MUTED,S.mono)
		var hint:=label("footer_hint","方向键选择  ·  回车确认",Rect2(w*.56,h-36,w*.44-56,30),12,S.MUTED);hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		if controls.has(prior_focus) and controls[prior_focus] is Button and not controls[prior_focus].disabled:controls[prior_focus].call_deferred("grab_focus")
		else:
			for node in controls.values():
				if node is Button and not node.disabled:node.call_deferred("grab_focus");break
	rebuilding=false;hud.queue_redraw()

func build_title(w: float,h: float) -> void:
	var icon:=TextureRect.new();icon.texture=badge;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.position=Vector2(58,44);icon.size=Vector2(36,36);icon.modulate=S.BRASS;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(icon)
	label("mark","封锁区域  /  RESTRICTED AREA",Rect2(110,47,w*.65,30*font_factor),13,S.BRASS,S.mono)
	label("title","银行危机",Rect2(52,h*.18,w*.52,96*font_factor),72,S.PAPER,S.title)
	label("subtitle","B A N K   C R I S I S",Rect2(58,h*.18+98*font_factor,w*.48,35*font_factor),18,S.MUTED,S.mono)
	var y: float=maxf(h*.45,h*.18+152*font_factor);var height: float=46*font_factor;var width: float=minf(410*font_factor,w*.43)
	button("start","01    "+("继续探索" if has_run else "进入银行"),Rect2(58,y,width,height),func():set_mode("play") if has_run else begin_game())
	button("title_settings","02    行动设置",Rect2(58,y+(height+8),width,height),func():open_page("settings"))
	button("title_help","03    操作手册",Rect2(58,y+(height+8)*2,width,height),func():open_page("help"))
	button("quit","04    退出游戏",Rect2(58,y+(height+8)*3,width,height),func():confirm("quit"))
	button("multiplayer","多人合作 / 创建或加入会话",Rect2(w*.61,h*.66,w*.32,48*font_factor),func():world.coop.open_menu())
	plate(Rect2(w*.62,h*.37,w*.30,h*.23),"",true)
	label("building_label","建筑档案 / 04 FLOORS",Rect2(w*.62,h*.37-35*font_factor,w*.30,30*font_factor),13,S.BRASS,S.mono)
	label("title_note","保持安静。留意每一扇门。",Rect2(w*.62,h*.77,w*.30,70*font_factor),17,S.PAPER,null,true)

func build_pause(w: float,h: float) -> void:
	header("FIELD RECORD  /  PAUSED","暂时离开","现场已暂停。")
	var y:=content_top();var width: float=minf(390*font_factor,w*.43);var step:=minf(60*font_factor,(h-y-90)/5)
	button("resume","01    继续探索",Rect2(56,y,width,48*font_factor),func():set_mode("play"))
	button("equipment","02    随身装备",Rect2(56,y+step,width,48*font_factor),func():selected_item=world.firearms.selected;set_mode("loadout"))
	button("pause_settings","03    行动设置",Rect2(56,y+step*2,width,48*font_factor),func():open_page("settings"))
	button("restart","04    重新开始",Rect2(56,y+step*3,width,48*font_factor),func():confirm("restart"))
	button("to_title","05    返回主菜单",Rect2(56,y+step*4,width,48*font_factor),func():AppFlow.return_menu())
	button("multiplayer","多人合作 / 创建或加入",Rect2(w*.61,h-122,w*.32,48*font_factor),func():AppFlow.return_menu("multiplayer"))
	var x: float=w*.61;rule(Vector2(x,content_top()+18),w*.3,S.BRASS)
	label("pause_location",floor_code()+" / "+location_name(),Rect2(x,content_top()+40,w*.32,55*font_factor),26,S.PAPER,S.title)
	var record_top:=content_top()+40+70*font_factor
	label("pause_record","当前记录\n\n生命  %03d / 100\n已击倒  %02d\n携带  %s"%[ceili(world.player_hp),world.kills,LABELS[world.firearms.selected]],Rect2(x,record_top,w*.32,back_y()-record_top-20),18,S.MUTED,null,true)

func build_settings(w: float,h: float) -> void:
	header("PERSONAL CONFIGURATION","行动设置","调整听觉、视角控制与文字可读性。")
	var y:=content_top()+8;var row_h: float=minf(90*font_factor,(back_y()-y-32)/3);var x: float=w*.60
	panel(Rect2(56,y-12,w-112,row_h*3+20))
	for i in range(3):
		var row: float=y+i*row_h
		label("setting_label_"+str(i),["总音量","鼠标灵敏度","界面文字"][i],Rect2(80,row+7,w*.4,32*font_factor),20)
		label("setting_note_"+str(i),["武器、感染者与环境声音","水平与垂直视角转动速度","提高 HUD 和菜单文字的辨识度"][i],Rect2(80,row+43*font_factor,w*.45,30*font_factor),13,S.MUTED)
		if i<2:
			var key: String="volume" if i==0 else "sensitivity"
			button(key+"_less","−",Rect2(x,row+15,50*font_factor,44*font_factor),func():change_setting(key,-.1))
			label(key+"_value",str(roundi(settings.volume*100))+" %" if i==0 else "%.1f ×"%settings.sensitivity,Rect2(x+60*font_factor,row+17,100*font_factor,42*font_factor),22,S.BRASS,S.mono)
			button(key+"_more","+",Rect2(x+167*font_factor,row+15,50*font_factor,44*font_factor),func():change_setting(key,.1))
		else:button("text_size","放大" if settings.large_text else "标准",Rect2(x,row+15,217*font_factor,44*font_factor),func():change_setting("large_text",0))
	button("back","返回",Rect2(56,back_y(),180*font_factor,48*font_factor),close_page)
	label("settings_save","设置自动保存在本机",Rect2(250*font_factor,back_y()+11,w-250*font_factor-56,35*font_factor),13,S.MUTED)

func build_loadout(w: float,h: float) -> void:
	header("PERSONAL EFFECTS  /  EQUIPMENT","随身装备","选择装备，准备下一次交战。")
	var left_w: float=w*.28;var x: float=w*.37;var right_w: float=w-x-56
	var top:=content_top()+4;var row_step:=minf(76*font_factor,(back_y()-top-24)/4)
	for i in range(4):
		var key: String=["pistol","shotgun","torch","baton"][i]
		var node:=button("item_"+key,"%02d   "% (i+1)+LABELS[key]+("  ·" if key==world.firearms.selected else ""),Rect2(56,top+i*row_step,left_w,minf(64*font_factor,row_step-12)),func():selected_item=key;rebuild())
		if key==selected_item:node.add_theme_stylebox_override("normal",S.box(Color("2e3930"),S.BRASS))
	var plate_height:=minf(210*font_factor,maxf(100,back_y()-top-20-184*font_factor))
	plate(Rect2(x,top,right_w,plate_height),selected_item)
	var bottom: float=top+plate_height
	label("item_name",LABELS[selected_item],Rect2(x,bottom+16*font_factor,right_w,40*font_factor),28,S.PAPER,S.title)
	label("item_description",DESCRIPTIONS[selected_item],Rect2(x,bottom+66*font_factor,right_w,72*font_factor),16,S.MUTED,null,true)
	var status_text: String="近战工具" if selected_item=="baton" else "照明工具" if selected_item=="torch" else "弹仓  %02d / %02d   ·   备弹 %s"%[world.firearms.ammo[selected_item].clip,world.firearms.data.weapons[selected_item].capacity,"∞" if world.firearms.ammo[selected_item].reserve<0 else str(world.firearms.ammo[selected_item].reserve)]
	label("item_ammo",status_text,Rect2(x,bottom+144*font_factor,right_w,28*font_factor),16,S.BRASS)
	var equip:=button("equip","已装备" if selected_item==world.firearms.selected else "装备并返回",Rect2(x,back_y(),250*font_factor,48*font_factor),func():world.firearms.select_weapon(selected_item);set_mode("play"))
	equip.disabled=selected_item==world.firearms.selected or world.feedback.is_grabbed()
	button("back","返回现场",Rect2(56,back_y(),210*font_factor,48*font_factor),func():set_mode("play"))

func build_help(w: float,h: float) -> void:
	header("SURVIVAL NOTES  /  CONTROLS","操作手册","熟悉装备，再走进黑暗。")
	var pairs: Array=[["W A S D","移动"],["SHIFT","奔跑"],["鼠标左键","射击 / 近战攻击"],["鼠标右键","推开 / 被抓时挣脱"],["R","装填弹药"],["1 / 2 / 3 / 4","切换四种装备"],["E","开关门"],["F","开关光源"],["TAB","随身装备"],["ESC","暂停 / 返回"]]
	for i in range(pairs.size()):
		var col: int=i/5;var row: int=i%5;var x: float=56+col*(w*.5);var y: float=content_top()+8+row*minf(68*font_factor,(back_y()-content_top()-32)/5)
		rule(Vector2(x,y+54*font_factor),w*.5-112)
		label("help_key_"+str(i),pairs[i][0],Rect2(x,y,w*.20,40*font_factor),17,S.BRASS,S.mono)
		label("help_text_"+str(i),pairs[i][1],Rect2(x+w*.20,y,w*.25-56,44*font_factor),16,S.PAPER,null,true)
	button("back","返回",Rect2(56,back_y(),180*font_factor,48*font_factor),close_page)

func build_death(w: float,h: float) -> void:
	header("SIGNAL LOST  /  END OF RECORD","生命信号中断")
	rule(Vector2(56,content_top()-20),minf(530,w*.5),S.DANGER)
	label("death_copy","你没能离开这里。",Rect2(56,content_top()+6,w*.5,60*font_factor),25,S.PAPER,S.title)
	label("death_record",floor_code()+"  /  "+location_name()+"\n\n本次击倒  %02d"%world.kills,Rect2(56,content_top()+90*font_factor,w*.50,116*font_factor),19,S.MUTED,null,true)
	button("retry","R    重新开始",Rect2(56,back_y()-74*font_factor,310*font_factor,52*font_factor),begin_game)
	button("death_title","返回主菜单",Rect2(56,back_y()-12,310*font_factor,48*font_factor),func():AppFlow.return_menu())
	label("death_seal","记录终止",Rect2(w*.66,h*.46,w*.27,75*font_factor),40,S.DANGER,S.title)

func build_confirm(w: float,h: float) -> void:
	header("CONFIRM ACTION","结束当前记录？")
	var top:=content_top()+8
	panel(Rect2(56,top,w-112,210*font_factor))
	label("confirm_copy","退出游戏将结束本次探索。" if pending_confirm=="quit" else "生命、弹药和敌人将恢复为本次探索的初始状态。",Rect2(84,top+20,w-168,85*font_factor),22,S.PAPER,null,true)
	label("confirm_note","当前版本不保存探索进度。",Rect2(84,top+130*font_factor,w-168,40*font_factor),16,S.MUTED)
	button("cancel","返回",Rect2(56,back_y(50)-20,210*font_factor,50*font_factor),func():set_mode(return_mode))
	button("confirm","确认退出" if pending_confirm=="quit" else "重新开始",Rect2(290*font_factor,back_y(50)-20,260*font_factor,50*font_factor),confirm_action)

func inspect() -> Dictionary:
	var values: Dictionary={};var visible_rect:=get_viewport().get_visible_rect()
	for id in controls:
		var node: Control=controls[id]
		var rect:=node.get_global_rect()
		values[id]={"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"visible":node.is_visible_in_tree(),"text":node.text if node is Label or node is Button else "","font_size":node.get_theme_font_size("font_size"),"focus":node.has_focus(),"disabled":node.disabled if node is Button else false}
	return {"viewport":[visible_rect.size.x,visible_rect.size.y],"physical_size":[get_window().size.x,get_window().size.y],"scale":get_viewport().get_final_transform().get_scale().x,"controls":values,"mode":mode}

func observe() -> Dictionary:
	return {"mode":mode,"paused":blocks_world(),"selected_item":selected_item,"settings":settings.duplicate(),"hud":hud.observe(),"font_factor":font_factor,"has_run":has_run}

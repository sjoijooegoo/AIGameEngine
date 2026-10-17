extends Control
## View-only binding to gameplay. No ammo, health or interaction rules here.
const S=preload("res://ui/style.gd")
const ICONS={"pistol":preload("res://ui/icons/pistol.svg"),"shotgun":preload("res://ui/icons/shotgun.svg"),"torch":preload("res://ui/icons/torch.svg"),"baton":preload("res://ui/icons/baton.svg")}
var shell: CanvasLayer
var world: Node3D
var health_display:=100.0
var switch_time:=0.0
var previous_weapon:=""
var door_id:=""
var location:=""
var message:=""
var clock:=0.0
var fps_clock:=0.0
var fps_text:="FPS  --"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE;S.fonts()

func _process(dt: float) -> void:
	# Render FPS is independent of the fixed gameplay clock and profiler.
	fps_clock+=dt
	if fps_clock<.25:return
	fps_clock=0.0
	var fps:=Engine.get_frames_per_second()
	fps_text="FPS  %d"%fps if fps>0 else "FPS  --"
	if is_visible_in_tree():queue_redraw()

func advance(dt: float) -> void:
	clock+=dt;health_display=move_toward(health_display,world.player_hp,dt*48)
	if previous_weapon!=world.firearms.selected:previous_weapon=world.firearms.selected;switch_time=2.8
	switch_time=maxf(0,switch_time-dt);door_id=world.aimed_door();location=shell.location_name()
	message=""
	if world.feedback.is_grabbed():message="挣脱控制"
	elif not door_id.is_empty():message=("关闭" if world.doors[door_id].target>.5 else "打开")+" · "+str(world.doors[door_id].definition.label)
	elif world.firearms.selected in ["pistol","shotgun"] and world.firearms.ammo[world.firearms.selected].clip==0 and not world.firearms.phase.begins_with("reload") and world.firearms.phase!="insert_shell":message="弹匣已空 · 按 R 装填"
	queue_redraw()

func text(at: Vector2,value: String,font_size: int,color: Color=S.PAPER,font: Font=null) -> void:
	draw_string(S.body if font==null else font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(font_size*shell.font_factor),color)

func line(a: Vector2,b: Vector2,color: Color=S.LINE,width:=1.0) -> void:draw_line(a,b,color,width,true)

func icon(key: String,rect: Rect2,color: Color) -> void:
	var texture: Texture2D=ICONS[key];var original:=texture.get_size()
	var fitted: Vector2=original*minf(rect.size.x/original.x,rect.size.y/original.y)
	draw_texture_rect(texture,Rect2(rect.position+(rect.size-fitted)*.5,fitted),false,color)

func _draw() -> void:
	if not world or world.player_dead or shell.mode!="play":return
	var u: float=shell.font_factor
	var w:=size.x;var h:=size.y;var margin:=32.0
	# Small location header; the screen centre stays clear until an interaction.
	draw_rect(Rect2(margin,28,3,36*u),S.BRASS)
	text(Vector2(margin+15,42*u),shell.floor_code()+"  /  "+location,16,S.PAPER)
	text(Vector2(margin+15,65*u),"隔离区  ·  银行大楼",12,S.MUTED)
	draw_rect(Rect2(margin+9,73*u,104*u,25*u),Color(.035,.06,.052,.75))
	text(Vector2(margin+15,91*u),fps_text,16,S.PAPER,S.mono)
	var bar_width:=208.0*u;var base:=Vector2(margin,h-40)
	draw_rect(Rect2(base-Vector2(12,100*u),Vector2(bar_width+64,116*u)),Color(.035,.06,.052,.67))
	var color: Color=S.DANGER if world.player_hp<=30 else S.BRASS if world.player_hp<=60 else S.PAPER
	text(base+Vector2(0,-73*u),"生命体征",13,S.MUTED)
	text(base+Vector2(0,-30*u),"%03d"%ceili(world.player_hp),38,color,S.mono)
	text(base+Vector2(103*u,-32*u),"危急" if world.player_hp<=30 else "受伤" if world.player_hp<=60 else "稳定",17,color)
	for i in range(20):
		var rect:=Rect2(base+Vector2(i*bar_width/20,-13*u),Vector2(bar_width/20-3,5*u))
		draw_rect(rect,Color("39453d"))
		if i<float(health_display)/5:draw_rect(rect,Color("7c6348"))
		if i<float(world.player_hp)/5:draw_rect(rect,color)
	# Minimal pulse trace, bounded and tied to simulation time.
	var pulse:=PackedVector2Array()
	for i in range(37):
		var phase:=fposmod(i/36.0+clock*.65,1.0)
		var value: float=-10*exp(-pow((phase-.48)*35,2))+5*exp(-pow((phase-.58)*24,2))
		pulse.append(base+Vector2(bar_width+13+i*.65,-50*u+value*u))
	draw_polyline(pulse,Color(color,.65),1,true)
	# Equipment and ammunition share the same fixed lower-right anchor.
	var gun=world.firearms;var key: String=gun.selected
	var right:=Vector2(w-margin-264*u,h-40)
	draw_rect(Rect2(right-Vector2(12,100*u),Vector2(288*u,116*u)),Color(.035,.06,.052,.73))
	text(right+Vector2(0,-73*u),{"pistol":"半自动手枪","shotgun":"泵动霰弹枪","torch":"手电筒","baton":"警棍"}[key],14,S.PAPER)
	icon(key,Rect2(right+Vector2(0,-57*u),Vector2(91*u,40*u)),Color(S.MUTED,.85))
	if key in ["pistol","shotgun"]:
		var ammo: Dictionary=gun.ammo[key]
		text(right+Vector2(107*u,-27*u),"%02d"%ammo.clip,38,S.DANGER if ammo.clip==0 else S.PAPER,S.mono)
		text(right+Vector2(166*u,-28*u),"/ "+("∞" if ammo.reserve<0 else "%02d"%ammo.reserve),20,S.MUTED,S.mono)
		var reloading: bool=gun.phase.begins_with("reload") or gun.phase=="insert_shell"
		if reloading:
			text(right+Vector2(0,4*u),"装填中",12,S.BRASS)
			line(right+Vector2(78*u,0),right+Vector2(256*u,0),S.LINE,2)
			line(right+Vector2(78*u,0),right+Vector2((78+178*clampf(gun.phase_time/gun.duration,0,1))*u,0),S.BRASS,2)
		else:
			var capacity: int=gun.data.weapons[key].capacity
			for i in capacity:draw_rect(Rect2(right+Vector2(i*11*u,-7*u),Vector2(7*u,6*u)),S.BRASS if i<int(ammo.clip) else Color("3c473d"))
	else:
		text(right+Vector2(109*u,-31*u),"三段连击" if key=="baton" else "照明开启" if world.flashlight.visible else "照明关闭",20,S.PAPER)
		text(right+Vector2(0,3*u),"左键攻击  /  右键推开" if key=="baton" else "F  开关光源",12,S.MUTED)
	# These hints replace the former full-width debug sentence.
	text(Vector2(w-margin-190*u,40*u),"1–4  装备    ESC  会话" if world.has_method("is_coop_active") and world.is_coop_active() else "TAB  装备     ESC  暂停",12,S.MUTED,S.mono)
	if switch_time>0:
		var x: float=w*.5-132*u
		var strip_y: float=h-160*u if w<850*u else h-74*u
		for i in range(4):
			var item: String=["pistol","shotgun","torch","baton"][i];var selected: bool=item==key
			var rect:=Rect2(x+i*66*u,strip_y,58*u,34*u)
			draw_rect(rect,Color(.07,.10,.09,.8));line(rect.position+Vector2(0,34*u),rect.end,S.BRASS if selected else S.LINE,2 if selected else 1)
			icon(item,Rect2(rect.position+Vector2(4,0),Vector2(50,23)*u),S.BRASS if selected else S.MUTED)
			text(rect.position+Vector2(5,31)*u,str(i+1),10,S.BRASS if selected else S.MUTED,S.mono)
	if not message.is_empty():
		var grab: bool=world.feedback.is_grabbed();var width: float=(390 if grab else 350)*u
		var top:=Vector2(w*.5-width*.5,h*.64)
		draw_rect(Rect2(top,Vector2(width,(82 if grab else 48)*u)),Color(.045,.065,.056,.91))
		line(top,top+Vector2(width,0),S.DANGER if grab else S.BRASS,2)
		text(top+Vector2(16,31)*u,("右键  推开  /  A · D  挣扎" if grab else "[ E ]  "+message if not door_id.is_empty() else message),16,S.DANGER if grab else S.PAPER)
		if grab:
			for i in range(6):draw_rect(Rect2(top+Vector2(16+i*59,54)*u,Vector2(50,5)*u),S.DANGER if i<world.feedback.struggles else S.LINE)

func observe() -> Dictionary:
	return {"health":world.player_hp,"health_display":health_display,"weapon":world.firearms.selected,"door":door_id,"prompt":message,"location":location,"flashlight":world.flashlight.visible,"grabbed":world.feedback.is_grabbed(),"ammo":world.firearms.ammo.duplicate(true)}

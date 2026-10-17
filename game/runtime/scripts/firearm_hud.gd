extends Control
var weapon
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	if not weapon or weapon.world.player_dead:return
	var center:=size*.5
	var u: float=maxf(1,1/maxf(.45,get_viewport().get_final_transform().get_scale().x))
	if weapon.selected=="torch":draw_circle(center,1.5*u,Color("e4dcc7"));return
	var gap: float=(5.0+weapon.bloom*1.4+(6.0 if weapon.selected=="shotgun" else 0.0))*u
	var col:=Color("e4dcc7")
	if weapon.selected=="baton":
		draw_circle(center,2.5*u,Color(0,0,0,.8));draw_circle(center,1.2*u,col)
	else:
		for axis in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			draw_line(center+axis*gap,center+axis*(gap+6*u),Color(0,0,0,.8),3*u)
			draw_line(center+axis*gap,center+axis*(gap+6*u),col,u)
	if weapon.hit_time>0:
		var hit_col:=Color("e7765e") if weapon.last_kill else Color("e8b878") if weapon.last_headshot else Color("e1e8d5")
		hit_col.a=minf(1,weapon.hit_time/.08)
		var pulse: float=1.0+minf(.22,weapon.hit_time)*6
		for axis in [Vector2(1,1),Vector2(1,-1),Vector2(-1,1),Vector2(-1,-1)]:draw_line(center+axis*(6+pulse)*u,center+axis*(10+pulse)*u,hit_col,(2.0 if weapon.last_kill else 1.5)*u)
	elif weapon.corpse_time>0:
		var corpse_col:=Color(.65,.68,.63,minf(1,weapon.corpse_time/.06)*.8)
		draw_arc(center,(4.0+(1-weapon.corpse_time/.14)*2)*u,0,TAU,20,corpse_col,u)

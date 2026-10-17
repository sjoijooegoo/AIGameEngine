extends Control
const S=preload("res://ui/style.gd")
const ICONS=preload("res://ui/hud.gd").ICONS
var weapon:="pistol"
var building:=false
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var w:=size.x;var h:=size.y
	draw_rect(Rect2(Vector2.ZERO,size),Color(.025,.042,.036,.48))
	for x in range(0,int(w),32):draw_line(Vector2(x,0),Vector2(x,h),Color(.30,.36,.29,.13))
	for y in range(0,int(h),32):draw_line(Vector2(0,y),Vector2(w,y),Color(.30,.36,.29,.13))
	for corner in [Vector2.ZERO,Vector2(w,0),Vector2(0,h),size]:
		var inward:=Vector2(1 if corner.x==0 else -1,1 if corner.y==0 else -1)
		draw_line(corner,corner+Vector2(20*inward.x,0),S.BRASS,1)
		draw_line(corner,corner+Vector2(0,20*inward.y),S.BRASS,1)
	if building:
		for i in range(4):
			var y: float=h*.22+i*h*.16
			draw_rect(Rect2(w*.23,y,w*.59,h*.12),Color(.5,.6,.47,.12))
			draw_line(Vector2(w*.23,y),Vector2(w*.82,y),S.LINE,1)
			draw_string(S.mono,Vector2(w*.08,y+17),"%02d"%(4-i),HORIZONTAL_ALIGNMENT_LEFT,-1,14,S.BRASS)
			for j in range(6):draw_rect(Rect2(w*(.28+j*.085),y+8,w*.04,h*.06),Color(.5,.6,.47,.25))
	else:
		var texture: Texture2D=ICONS[weapon];var ratio:=float(texture.get_width())/texture.get_height()
		var width: float=minf(w*.8,h*.60*ratio);var height: float=width/ratio
		draw_texture_rect(texture,Rect2(Vector2((w-width)*.5,h*.43-height*.5),Vector2(width,height)),false,S.PAPER)
		draw_line(Vector2(w*.10,h*.78),Vector2(w*.90,h*.78),S.LINE)
		for i in range(17):draw_line(Vector2(w*(.1+i*.05),h*.78),Vector2(w*(.1+i*.05),h*.78+(8 if i%4==0 else 4)),S.LINE)

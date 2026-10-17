extends RefCounted
## Bank UI tokens. Native controls, HUD and vector plates share this palette.
const PAPER=Color("e4dcc7")
const MUTED=Color("a3ad9c")
const BRASS=Color("c5a56e")
const INK=Color("121a19")
const LINE=Color("536056")
const DANGER=Color("d47768")
static var body: SystemFont
static var title: SystemFont
static var mono: SystemFont

static func fonts() -> void:
	if body!=null:return
	body=SystemFont.new();body.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC"])
	title=SystemFont.new();title.font_names=PackedStringArray(["SimSun","Noto Serif CJK SC"])
	mono=SystemFont.new();mono.font_names=PackedStringArray(["Consolas","DejaVu Sans Mono"])

static func box(background: Color,border: Color=Color.TRANSPARENT,width: int=1) -> StyleBoxFlat:
	var b:=StyleBoxFlat.new();b.bg_color=background;b.border_color=border;b.set_border_width_all(width)
	b.content_margin_left=18;b.content_margin_right=18;b.content_margin_top=10;b.content_margin_bottom=10
	return b

static func theme_for(font_scale: float) -> Theme:
	fonts();var t:=Theme.new();t.default_font=body;t.default_font_size=roundi(18*font_scale)
	t.set_color("font_color","Label",PAPER)
	t.set_color("font_color","Button",PAPER);t.set_color("font_hover_color","Button",Color.WHITE)
	t.set_color("font_focus_color","Button",PAPER);t.set_color("font_pressed_color","Button",INK)
	t.set_color("font_disabled_color","Button",Color("748074"))
	t.set_stylebox("normal","Button",box(Color(.07,.10,.09,.82),Color("465347")))
	t.set_stylebox("hover","Button",box(Color("364139"),BRASS))
	t.set_stylebox("pressed","Button",box(BRASS,BRASS))
	t.set_stylebox("focus","Button",box(Color.TRANSPARENT,BRASS,2))
	t.set_stylebox("disabled","Button",box(Color(.07,.1,.09,.4),Color("344037")))
	return t

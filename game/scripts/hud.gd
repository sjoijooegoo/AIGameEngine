extends CanvasLayer

signal resume_requested
signal restart_requested
signal save_requested
signal load_requested

var root: Control
var health: Label
var objective: Label
var prompt: Label
var inventory: PanelContainer
var inventory_text: Label
var pause_panel: PanelContainer
var controls: Dictionary = {}

func _ready() -> void:
	root = Control.new()
	root.name = "HUD"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	theme.default_font = font
	theme.default_font_size = 18
	root.theme = theme
	var top := _panel("top_bar", root, Color("122533"))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 22
	top.offset_bottom = 108
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	top.add_child(row)
	var title := _label("title", "银行危机 / 开发试验场", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	health = _label("health", "体力 100", 22)
	row.add_child(health)
	objective = _label("objective", "找到门卡，穿过安全门", 17)
	objective.position = Vector2(40, 125)
	root.add_child(objective)
	prompt = _label("prompt", "", 19)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -260
	prompt.offset_right = 260
	prompt.offset_top = -124
	prompt.offset_bottom = -88
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt)
	var footer_panel := _panel("footer", root, Color("122533"))
	footer_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer_panel.offset_left = 24
	footer_panel.offset_right = -24
	footer_panel.offset_top = -76
	footer_panel.offset_bottom = -20
	footer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var footer := _label("help", "WASD 移动   Shift 奔跑   E 调查   左键攻击   Tab 背包   Esc 暂停", 16)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_panel.add_child(footer)
	inventory = _dialog("inventory", "随身物品")
	inventory_text = _label("inventory_items", "暂无物品", 20)
	inventory.get_child(0).add_child(inventory_text)
	inventory.visible = false
	pause_panel = _dialog("pause", "暂停")
	var column: VBoxContainer = pause_panel.get_child(0)
	_button(column, "resume", "继续游戏", func(): resume_requested.emit())
	_button(column, "save", "保存进度", func(): save_requested.emit())
	_button(column, "load", "读取进度", func(): load_requested.emit())
	_button(column, "restart", "重新开始", func(): restart_requested.emit())
	pause_panel.visible = false

func _panel(id: String, parent: Node, color: Color) -> PanelContainer:
	var node := PanelContainer.new()
	node.name = id
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("597382")
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	controls[id] = node
	return node

func _label(id: String, text: String, size: int) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("edf3f5"))
	controls[id] = label
	return label

func _dialog(id: String, title: String) -> PanelContainer:
	var panel := _panel(id, root, Color("193444"))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -175
	panel.offset_bottom = 175
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(_label(id + "_title", title, 26))
	return panel

func _button(parent: Node, id: String, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size.y = 44
	button.pressed.connect(callback)
	parent.add_child(button)
	controls[id] = button

func refresh(hp: float, keys: Array, complete: bool, hint: String) -> void:
	health.text = "体力 %03d" % int(hp)
	objective.text = "已通过安全门 · 测试流程完成" if complete else "找到门卡，穿过安全门"
	prompt.text = hint
	inventory_text.text = "蓝色门卡 × 1" if "access_card" in keys else "暂无物品"

func inspect() -> Dictionary:
	var result := {}
	var viewport_size := root.get_viewport_rect().size
	for id in controls:
		var c: Control = controls[id]
		var rect := c.get_global_rect()
		var visible := c.is_visible_in_tree()
		var entry := {"visible": visible, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "inside_viewport": Rect2(Vector2.ZERO, viewport_size).encloses(rect)}
		if c is Label or c is Button:
			entry["text"] = c.text
			entry["minimum_size"] = [c.get_combined_minimum_size().x, c.get_combined_minimum_size().y]
		if c is Button:
			entry["disabled"] = c.disabled
		result[id] = entry
	return {"viewport": [viewport_size.x, viewport_size.y], "controls": result}

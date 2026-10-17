extends Control
## Game state belongs to this fixture; plugins consume it via explicit interfaces.
var has_keycard := false
var alert := false
var paused := false
var testing := false
var ticks := 0
var ai_ticks := 0
var ai_mode := "巡逻"
var ai_progress := 0.0
var busy := false
var line: DialogueLine
var dialogue: DialogueResource
var bt: BTPlayer
var text_label: Label
var status_label: Label
var progress: ProgressBar
var controls := {}

func _ready() -> void:
	Input.use_accumulated_input = false
	dialogue = load("res://systems/terminal.dialogue")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 22
	var background := ColorRect.new()
	background.color = Color("172431")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var title := Label.new()
	title.text = "插件试验场 / 文本与行为树"
	title.add_theme_font_size_override("font_size", 34)
	column.add_child(title)
	var help := Label.new()
	help.text = "E 调查 / 继续   ·   K 门卡   ·   F 警戒   ·   空格 暂停 AI"
	column.add_child(help)
	status_label = Label.new()
	column.add_child(status_label)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 28
	progress.show_percentage = false
	column.add_child(progress)
	text_label = Label.new()
	text_label.text = "点击调查终端，或按 E 开始。\n所有文本均为试验素材，不代表原作最终规则。"
	text_label.custom_minimum_size.y = 110
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text_label)
	for id in ["next", "choice_1", "choice_2"]:
		var button := Button.new()
		button.custom_minimum_size.y = 48
		column.add_child(button)
		controls[id] = button
	controls.next.text = "调查终端 / 继续 [E]"
	controls.next.pressed.connect(advance_dialogue)
	controls.choice_1.pressed.connect(func(): choose(0))
	controls.choice_2.pressed.connect(func(): choose(1))
	controls.choice_1.hide()
	controls.choice_2.hide()
	bt = BTPlayer.new()
	bt.update_mode = BTPlayer.MANUAL
	bt.behavior_tree = BehaviorTree.new()
	bt.behavior_tree.set_root_task(preload("res://systems/ai_action.gd").new())
	bt.set_scene_root_hint(self)
	add_child(bt)
	bt.blackboard.set_var("alert", false)
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ai-session="):
				testing = true
				var bridge := preload("res://addons/ai_engine/testing/bridge.gd").new()
				bridge.session = arg.trim_prefix("--ai-session=")
				bridge.adapter = preload("res://systems/adapter.gd").new(self)
				add_child(bridge)
				break
	print("ADDON_SYSTEMS_READY ", JSON.stringify({"dialogue_loaded": dialogue != null, "manual_ai": bt.update_mode == BTPlayer.MANUAL, "debug_build": OS.is_debug_build(), "puzzle_editor_excluded": not ResourceLoader.exists("res://addons/puzzle_dependencies/plugin.gd")}))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: advance_dialogue()
			KEY_1: choose(0)
			KEY_2: choose(1)
			KEY_K: has_keycard = not has_keycard
			KEY_F:
				alert = not alert
				bt.blackboard.set_var("alert", alert)
			KEY_SPACE: paused = not paused

func advance_dialogue() -> void:
	if busy or (line != null and not line.responses.is_empty()):
		return
	load_line("start" if line == null else line.next_id)

func choose(index: int) -> void:
	if busy or line == null or index >= line.responses.size():
		return
	var response: DialogueResponse = line.responses[index]
	if response.is_allowed:
		load_line(response.next_id)

func load_line(cue: String) -> void:
	busy = true
	line = await dialogue.get_next_dialogue_line(cue, [self])
	text_label.text = (line.character + "：" + line.text) if line != null else "终端已关闭。可再次调查。"
	for index in range(2):
		var button: Button = controls["choice_%d" % (index + 1)]
		button.visible = line != null and index < line.responses.size()
		if button.visible:
			button.text = "%d  %s" % [index + 1, line.responses[index].text]
			button.disabled = not line.responses[index].is_allowed
	# Let container layout settle before reporting that interactive choices are ready.
	await get_tree().process_frame
	await get_tree().process_frame
	busy = false

func tick(dt: float) -> void:
	ticks += 1
	if not paused:
		bt.update(dt)

func _physics_process(dt: float) -> void:
	if not testing:
		tick(dt)

func _process(_dt: float) -> void:
	status_label.text = "门卡：%s   |   AI：%s%s   |   模拟帧：%d / AI 步数：%d" % ["有" if has_keycard else "无", ai_mode, "（暂停）" if paused else "", ticks, ai_ticks]
	progress.value = ai_progress * 100

func observe() -> Dictionary:
	return {"tick": ticks, "ai_ticks": ai_ticks, "ai_mode": ai_mode, "ai_progress": ai_progress, "alert": alert, "paused": paused, "has_keycard": has_keycard, "busy": busy, "text": text_label.text, "responses": line.responses.size() if line != null else 0, "dialogue_id": line.id if line != null else "", "manual_ai": bt.update_mode == BTPlayer.MANUAL}

func _exit_tree() -> void:
	# DM 4.1.0 injects data.resource into its own resource.lines dictionaries.
	# Break that self-reference on teardown of this single-resource fixture.
	# Imported dialogue graphs require a broader lifetime policy before adoption.
	line = null
	if dialogue != null:
		for data in dialogue.lines.values():
			if data is Dictionary and data.get("resource") == dialogue:
				data.erase("resource")
	dialogue = null

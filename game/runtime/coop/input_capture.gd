extends RefCounted
## End a gameplay capture with balanced button events before freeing the cursor.
static func release(viewport: Viewport) -> void:
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]:
		if not Input.is_mouse_button_pressed(button):continue
		var event:=InputEventMouseButton.new()
		event.button_index=button;event.pressed=false;event.button_mask=0
		event.position=viewport.get_mouse_position();event.global_position=event.position
		event.set_meta("ai_bridge_input",true)
		Input.parse_input_event(event)
	if viewport.gui_is_dragging():viewport.gui_cancel_drag()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

@tool
extends EditorPlugin
## Only activated by the local test CLI with an explicit evidence directory.
func _enter_tree() -> void:
	if not OS.get_environment("AIGE_ADDON_EDITOR_SESSION").is_empty():
		verify.call_deferred()

func verify() -> void:
	var directory := OS.get_environment("AIGE_ADDON_EDITOR_SESSION").simplify_path().replace("\\", "/")
	var allowed := ProjectSettings.globalize_path("res://../../../logs/runs").simplify_path().replace("\\", "/").trim_suffix("/")
	if directory.get_base_dir() != allowed or not DirAccess.dir_exists_absolute(directory):
		push_error("Invalid editor evidence directory")
		get_tree().quit(2)
		return
	for i in range(30):
		await get_tree().process_frame
	var main: Control = null
	for child in EditorInterface.get_editor_main_screen().get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("/puzzle_dependencies/views/main_view.gd"):
			main = child
	var result := {"puzzle_view_loaded": main != null, "dialogue_editor_enabled": EditorInterface.is_plugin_enabled("dialogue_manager"), "limboai_loaded": ClassDB.class_exists("BTPlayer")}
	if main != null:
		var data: Dictionary = main.board.to_serialized()
		result["things"] = data.things.size()
		result["connections"] = data.connections.size()
		result["board_id"] = main.current_board_id
		EditorInterface.set_main_screen_editor("Puzzles")
		for i in range(8):
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var picture := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
			result["capture_error"] = picture.save_png(directory.path_join("puzzle-editor.png"))
	var file := FileAccess.open(directory.path_join("editor-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	get_tree().quit()

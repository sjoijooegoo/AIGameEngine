extends SceneTree
## Preserve exact bake source bytes when a debug engine opens a release PCK.
## Exported scripts are tokenized; this overlay is only for local SSH validation.
func _initialize() -> void:
	var source := ""
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source=arg.trim_prefix("--source=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	assert(not source.is_empty() and not output.is_empty())
	var config=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("data/lighting_bake.json")))
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(source.path_join(str(config.output).trim_prefix("res://")).path_join("manifest.json")))
	var pack:=PCKPacker.new()
	assert(pack.pck_start(output)==OK)
	for resource in manifest.hashes:
		var path:=source.path_join(str(resource).trim_prefix("res://"))
		assert(FileAccess.get_sha256(path)==manifest.hashes[resource])
		assert(pack.add_file(resource,path)==OK)
	assert(pack.flush()==OK)
	print("BANK_VALIDATION_OVERLAY ",output)
	quit()

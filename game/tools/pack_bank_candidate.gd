extends SceneTree
## Debug validation overlay over a paired release asset pack. Never installed
## as the production server; final acceptance runs a full standalone export.
func _initialize() -> void:
	var source:="";var output:="";var paths:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--paths="):paths=arg.trim_prefix("--paths=")
	assert(not source.is_empty() and not output.is_empty())
	var resources=JSON.parse_string(FileAccess.get_file_as_string(paths));assert(resources is Array)
	var pack:=PCKPacker.new();assert(pack.pck_start(output)==OK)
	var manifest: Dictionary={}
	for resource: String in resources:
		assert(resource.begins_with("res://") and resource.ends_with(".gd") and not ".." in resource)
		var path:=source.path_join(resource.trim_prefix("res://"))
		manifest[resource]=FileAccess.get_sha256(path);assert(not manifest[resource].is_empty())
		assert(pack.add_file(resource,path)==OK)
		var remap_path:=output+"."+str(manifest.size())+".remap"
		var f:=FileAccess.open(remap_path,FileAccess.WRITE);f.store_string('[remap]\npath="'+resource+'"\n');f.close()
		assert(pack.add_file(resource+".remap",remap_path)==OK)
	var manifest_path:=output+".json"
	var f:=FileAccess.open(manifest_path,FileAccess.WRITE);f.store_string(JSON.stringify(manifest));f.close()
	assert(pack.add_file("res://candidate_manifest.json",manifest_path)==OK)
	assert(pack.flush()==OK);print("BANK_CANDIDATE_PACK ",output);quit()

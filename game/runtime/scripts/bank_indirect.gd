extends RefCounted
## Attach only a matching offline render snapshot. Live collisions are untouched.
static func mark(world: Node3D) -> void:
	var index:=0
	for visual in world.find_children("*","GeometryInstance3D",true,false):
		var parent: Node=visual;var moving:=false
		while parent!=null and parent!=world:
			if parent is SubViewport or parent in world.doors.values():moving=true;break
			parent=parent.get_parent()
		if not moving:
			visual.name="BankRenderSource_%05d"%index
			index+=1

static func attach(world: Node3D) -> Dictionary:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/lighting_bake.json"))
	var path: String=str(config.output)+"/manifest.json"
	if not FileAccess.file_exists(path):return {"loaded":false,"reason":"not_generated"}
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	# Candidates are visible only in an explicit isolated debug test process.
	# Normal play/export requires a separately recorded visual review.
	var preview: bool=OS.is_debug_build() and world.testing and OS.get_environment("BANK_LIGHTING_PREVIEW")=="1"
	if not bool(manifest.get("runtime_enabled",false)) and not preview:
		return {"loaded":false,"reason":"runtime_disabled"}
	if manifest.get("bake_mode","")!="indirect_only":return {"loaded":false,"reason":"incompatible_bake_mode"}
	for source in manifest.hashes:
		if not OS.has_feature("editor") and source.get_extension() in ["gd","gdshader"]:continue
		if FileAccess.get_sha256(source)!=manifest.hashes[source]:
			push_warning("Bank indirect light is stale; regenerate after changing "+source)
			return {"loaded":false,"reason":"stale","source":source}
	var baked: Node3D=(load(manifest.scene) as PackedScene).instantiate()
	# Anonymous parent names contain process-wide allocation counters. A menu
	# or a second visit changes those counters, but not the stable render IDs.
	# Match the complete ancestry with only those generated counters removed;
	# never accept a missing/ambiguous ID or bypass the source hashes above.
	var stable: Dictionary={}
	for visual in world.find_children("BankRenderSource_*","GeometryInstance3D",true,false):
		var key:=stable_path(str(world.get_path_to(visual)))
		if stable.has(key):stable[key]=null
		else:stable[key]=visual
	var originals: Array[GeometryInstance3D]=[]
	# Every expected original must exist before any render state is changed.
	for source in manifest.source_nodes:
		var visual=stable.get(stable_path(source))
		if not visual is GeometryInstance3D:
			baked.free();push_warning("Bank static snapshot does not match scene nodes")
			return {"loaded":false,"reason":"node_mismatch","source":source}
		originals.append(visual)
	world.add_child(baked)
	for visual in originals:visual.visible=false
	return {"loaded":true,"meshes":manifest.meshes,"preview":preview,"bake_mode":manifest.bake_mode}

static func stable_path(path: String) -> String:
	var parts:=path.split("/")
	for i in parts.size():
		if parts[i].begins_with("@"):
			var suffix:=parts[i].rfind("@")
			if suffix>0 and parts[i].substr(suffix+1).is_valid_int():parts[i]=parts[i].substr(0,suffix)
	return "/".join(parts)

extends RefCounted
## Share a material-batched intact skin across actors of the same source mesh.
## Alive and dead actors share this intact skin. UVs, normals, weights,
## skeleton, texture quality and silhouette are unchanged; internal caps omitted.
static var cache: Dictionary={}

static func create(parts: Dictionary) -> MeshInstance3D:
	var merged:=mesh_for(parts,false)
	if merged==null:return null
	var template: MeshInstance3D=parts.Body
	var result:=MeshInstance3D.new();result.name="IntactBatchedSkin"
	template.get_parent().add_child(result)
	result.transform=template.transform;result.mesh=merged;result.skin=template.skin;result.skeleton=template.skeleton
	return result

static func mesh_for(parts: Dictionary, headless: bool) -> ArrayMesh:
	if not parts.has("Body"):return null
	var template: MeshInstance3D=parts.Body
	var key: String=template.mesh.resource_path
	if key.is_empty():return null
	key+="/headless" if headless else "/intact"
	if not cache.has(key):
		var groups: Dictionary={}
		for name in parts:
			if headless and name=="Head":continue
			var part: MeshInstance3D=parts[name]
			# Only merge geometry with identical bind palettes and local coordinates.
			if part.get_parent()!=template.get_parent() or not part.transform.is_equal_approx(template.transform):return null
			if part.skin.get_bind_count()!=template.skin.get_bind_count():return null
			for i in template.skin.get_bind_count():
				if part.skin.get_bind_name(i)!=template.skin.get_bind_name(i) or part.skin.get_bind_bone(i)!=template.skin.get_bind_bone(i) or not part.skin.get_bind_pose(i).is_equal_approx(template.skin.get_bind_pose(i)):return null
			for surface in part.mesh.get_surface_count():
				var material: Material=part.mesh.surface_get_material(surface)
				# Existing prepared torso caps close the exposed neck. Arm/leg
				# caps lie inside their still-attached skin; no floating head mesh.
				if material.resource_name.begins_with("Cut_interior") and (not headless or name!="Body"):continue
				var format: int=part.mesh.surface_get_format(surface)
				var group: String=str(material.get_rid().get_id())+":"+str(format)
				if not groups.has(group):
					var st:=SurfaceTool.new()
					if format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:st.set_skin_weight_count(SurfaceTool.SKIN_8_WEIGHTS)
					st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(material);groups[group]=st
				groups[group].append_from(part.mesh,surface,Transform3D.IDENTITY)
		var merged:=ArrayMesh.new()
		for st in groups.values():st.commit(merged)
		cache[key]=merged
	return cache[key]

extends RefCounted
## Stationary bank geometry only. Floor slabs seal downward room spotlights;
## partition shadow casters conservatively, without hiding any world geometry.
## Doors remain on shared layer 1 and stair / exterior lights retain all layers.
static func prepare(world: Node3D) -> Dictionary:
	var groups: Dictionary={}
	var classified:=0;var merged:=0;var batches:=0
	for node in world.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if mesh.mesh==null or mesh.skin!=null:continue
		var parent: Node=mesh;var moving:=false
		while parent!=world:
			if parent in world.doors.values():moving=true;break
			parent=parent.get_parent()
		if moving:continue
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		var layers:=0
		# Include both rooms for slabs touching a floor boundary. This margin also
		# protects floating-point edge cases and small imported mesh tolerances.
		for level in range(clampi(floori((bounds.position.y-.04)/3.6),0,3),clampi(floori((bounds.end.y+.04)/3.6),0,3)+1):layers|=1 << (level+1)
		preload("res://scripts/render_layers.gd").assign(mesh,layers);classified+=1
		if mesh.mesh is BoxMesh or not mesh.is_visible_in_tree():continue
		var opaque:=true;var material_key:=""
		for i in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(i)
			if not material is StandardMaterial3D or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:opaque=false;break
			material_key+=":"+str(material.get_rid().get_id())
		if not opaque:continue
		var cell:=Vector3i(floor(bounds.get_center()/8.0))
		var key:=str(mesh.mesh.get_rid().get_id())+material_key+":"+str(layers)+":"+str(cell)+":"+str(mesh.cast_shadow)
		if not groups.has(key):groups[key]=[]
		groups[key].append(mesh)
	for group: Array in groups.values():
		if group.size()<2:continue
		var source: MeshInstance3D=group[0]
		# Surface overrides are baked into a shallow mesh copy, shared by this
		# batch; original imported resources and asset revisions stay untouched.
		var geometry: Mesh=source.mesh.duplicate()
		for i in geometry.get_surface_count():geometry.surface_set_material(i,source.get_active_material(i))
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=geometry;multi.instance_count=group.size()
		var source_transforms: Array[Transform3D]=[]
		for i in group.size():
			var transform: Transform3D=world.global_transform.affine_inverse()*group[i].global_transform
			source_transforms.append(transform);multi.set_instance_transform(i,transform)
		var instance:=MultiMeshInstance3D.new();instance.name="StaticPropBatch";instance.multimesh=multi
		instance.layers=source.layers;instance.cast_shadow=source.cast_shadow;world.add_child(instance)
		instance.set_meta("static_instance_transforms",source_transforms)
		for item: MeshInstance3D in group:item.mesh=null
		merged+=group.size();batches+=1
	return {"floor_classified":classified,"batched_props":merged,"prop_batches":batches}

extends RefCounted
## Batch opaque, stationary BoxMesh renderers by material and 8 m world cell.
## Their existing nodes/transforms/collision children stay in place. Call once
## after construction; moving objects and alpha materials must not be supplied.
static func build(parent: Node3D, meshes: Array, cell_size: float=8.0) -> Dictionary:
	var groups: Dictionary={}
	for mesh: MeshInstance3D in meshes:
		assert(mesh.get_parent()==parent and mesh.mesh is BoxMesh)
		var cell: Vector3i=Vector3i(floor(mesh.position/cell_size))
		# A batch must preserve the source light/camera layer contract.
		var key: String=str(mesh.material_override.get_rid().get_id())+":"+str(cell)+":"+str(mesh.layers)+":"+str(mesh.cast_shadow)
		if not groups.has(key):groups[key]=[]
		groups[key].append(mesh)
	var merged:=0;var batches:=0
	var cube:=BoxMesh.new();cube.size=Vector3.ONE
	for group: Array in groups.values():
		if group.size()<2:continue
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=cube;multi.instance_count=group.size()
		var source_transforms: Array[Transform3D]=[]
		for i in group.size():
			var source: MeshInstance3D=group[i]
			var transform: Transform3D=source.transform*Transform3D(Basis.from_scale(source.mesh.size),Vector3.ZERO)
			source_transforms.append(transform)
			multi.set_instance_transform(i,transform)
		var instance:=MultiMeshInstance3D.new();instance.multimesh=multi;instance.material_override=group[0].material_override
		instance.layers=group[0].layers;instance.cast_shadow=group[0].cast_shadow
		# Keep renderer-independent authored transforms for offline baking/audits.
		# Dummy/headless RenderingServer implementations cannot read GPU buffers.
		instance.set_meta("static_instance_transforms",source_transforms)
		parent.add_child(instance)
		for source: MeshInstance3D in group:source.mesh=null
		merged+=group.size();batches+=1
	return {"source_boxes":meshes.size(),"batched_boxes":merged,"draw_batches":batches,"cell_metres":cell_size}

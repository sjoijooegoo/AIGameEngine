extends RefCounted
## Continue the two open shirt rings behind the view camera. Only 24 boundary
## vertices are CPU skinned; fingers, grip, UVs and native animation stay intact.
var source: MeshInstance3D
var skeleton: Skeleton3D
var output: MeshInstance3D
var immediate:=ImmediateMesh.new()
var surfaces: Array=[]
var binds: Array=[]
var edge_count := 0
var ring_centers: Array=[]

func setup(model: Node3D) -> void:
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if "v_arms_louis" in str(mesh.name):source=mesh;break
	assert(source and source.skin,"Sleeve continuation needs the native arm skin")
	skeleton=source.get_node(source.skeleton)
	for i in source.skin.get_bind_count():
		var id: int=source.skin.get_bind_bone(i)
		if not source.skin.get_bind_name(i).is_empty():id=skeleton.find_bone(source.skin.get_bind_name(i))
		assert(id>=0);binds.append({"bone":id,"pose":source.skin.get_bind_pose(i)})
	for index in source.mesh.get_surface_count():
		var arrays: Array=source.mesh.surface_get_arrays(index)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var weld: Dictionary={};var welded: Array=[];var edges: Dictionary={}
		for v in vertices:
			var key:=Vector3i(roundi(v.x*100000),roundi(v.y*100000),roundi(v.z*100000))
			if not weld.has(key):weld[key]=weld.size()
			welded.append(weld[key])
		for triangle in range(0,indices.size(),3):
			for side in 3:
				var a:=indices[triangle+side];var b:=indices[triangle+(side+1)%3]
				var key:=Vector2i(mini(welded[a],welded[b]),maxi(welded[a],welded[b]))
				if edges.has(key):edges[key].count+=1
				else:edges[key]={"count":1,"a":a,"b":b}
		var boundary: Array=[]
		var border: Dictionary={}
		for e in edges.values():
			if e.count==1:boundary.append(e);border[welded[e.a]]=true;border[welded[e.b]]=true
		if boundary.is_empty():continue
		# Imported bind coordinates differ between weapon exports. Find each
		# ring by connectivity, never by the sign of a rest-space coordinate.
		var ring: Dictionary={};var ring_count:=0
		for seed_edge in boundary:
			var seed: int=welded[seed_edge.a]
			if ring.has(seed):continue
			var pending: Array=[seed];ring[seed]=ring_count
			while not pending.is_empty():
				var current: int=pending.pop_back()
				for edge in boundary:
					var a: int=welded[edge.a];var b: int=welded[edge.b]
					if a==current and not ring.has(b):ring[b]=ring_count;pending.append(b)
					if b==current and not ring.has(a):ring[a]=ring_count;pending.append(a)
			ring_count+=1
		assert(ring_count<=2)
		for edge in boundary:edge.side=ring[welded[edge.a]]
		var inner_uv: Dictionary={}
		for edge in boundary:
			for i in [edge.a,edge.b]:
				var distance:=INF;var nearest: int=i
				for j in vertices.size():
					if border.has(welded[j]):continue
					var d:=vertices[i].distance_squared_to(vertices[j])
					if d<distance:distance=d;nearest=j
				inner_uv[i]=arrays[Mesh.ARRAY_TEX_UV][nearest]
		# The source Louis mesh has exactly two 12-edge shoulder openings.
		# Reject unexpected topology instead of drawing over arbitrary UV seams.
		edge_count+=boundary.size()
		var material: StandardMaterial3D=source.get_active_material(index).duplicate()
		# The continuation has smooth normals but no UV tangent frame. Preserve
		# its shirt albedo rather than sampling a normal map without tangents.
		material.normal_enabled=false
		surfaces.append({"arrays":arrays,"edges":boundary,"material":material,"index":index,"inner_uv":inner_uv})
	assert(edge_count==24,"Unexpected native shoulder topology")
	output=MeshInstance3D.new();output.name="SleeveContinuation";output.mesh=immediate;output.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(output);output.top_level=true;output.global_transform=Transform3D.IDENTITY

func skin_point(index: int, arrays: Array, palette: Array) -> Vector3:
	var point:=Vector3.ZERO
	var stride: int=arrays[Mesh.ARRAY_BONES].size()/arrays[Mesh.ARRAY_VERTEX].size()
	for j in stride:
		var weight: float=arrays[Mesh.ARRAY_WEIGHTS][index*stride+j]
		if weight>0:point+=(palette[arrays[Mesh.ARRAY_BONES][index*stride+j]]*arrays[Mesh.ARRAY_VERTEX][index])*weight
	return skeleton.global_transform*point

func update() -> void:
	var palette: Array=[]
	for bind in binds:palette.append(skeleton.get_bone_global_pose(bind.bone)*bind.pose)
	immediate.clear_surfaces()
	for surface in surfaces:
		var points: Dictionary={};var centers: Array=[Vector3.ZERO,Vector3.ZERO];var counts: Array=[0,0]
		for edge in surface.edges:
			for i in [edge.a,edge.b]:
				if points.has(i):continue
				var p:=skin_point(i,surface.arrays,palette)
				var side: int=edge.side
				points[i]={"p":p,"side":side};centers[side]+=p;counts[side]+=1
		for side in 2:
			if counts[side]>0:centers[side]/=counts[side]
		ring_centers=centers.duplicate()
		var visible_edges: Array=[]
		for edge in surface.edges:
			if centers[points[edge.a].side].z<-.02:visible_edges.append(edge)
		if visible_edges.is_empty():continue
		immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES,surface.material)
		for edge in visible_edges:
			var a: Vector3=points[edge.a].p;var b: Vector3=points[edge.b].p;var center: Vector3=centers[points[edge.a].side]
			# Continue outwards on the ring's own side of the camera. A fixed
			# opposite shoulder anchor could cross the frustum during a swing.
			var tail:=Vector3(signf(center.x)*maxf(.48,absf(center.x)*3),minf(-.65,center.y*3) if center.y<0 else maxf(.65,center.y*3),.12)
			var aa:=tail+(a-center)*1.2;var bb:=tail+(b-center)*1.2
			var uv_a: Vector2=surface.arrays[Mesh.ARRAY_TEX_UV][edge.a];var uv_b: Vector2=surface.arrays[Mesh.ARRAY_TEX_UV][edge.b]
			for triangle in [[b,a,aa],[b,aa,bb]]:
				for v in triangle:
					var normal: Vector3=((b if v==b or v==bb else a)-center).normalized()
					var uv: Vector2=uv_b if v==b or v==bb else uv_a
					if v==aa or v==bb:uv=surface.inner_uv[edge.b if v==bb else edge.a]
					immediate.surface_set_normal(normal);immediate.surface_set_uv(uv);immediate.surface_add_vertex(v)
		immediate.surface_end()

func boundary_error() -> float:
	# Inspection only: compare the lightweight ring deformation to Godot's
	# full skin bake. Never perform this costly bake in the game loop.
	var baked: Mesh=source.bake_mesh_from_current_skeleton_pose()
	var palette: Array=[]
	for bind in binds:palette.append(skeleton.get_bone_global_pose(bind.bone)*bind.pose)
	var error:=0.0
	for surface in surfaces:
		var positions: PackedVector3Array=baked.surface_get_arrays(surface.index)[Mesh.ARRAY_VERTEX]
		for edge in surface.edges:
			for i in [edge.a,edge.b]:error=maxf(error,skin_point(i,surface.arrays,palette).distance_to(source.global_transform*positions[i]))
	return error

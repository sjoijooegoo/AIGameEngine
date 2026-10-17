extends RefCounted
## Keep source door maps. Sample the same baked field as the room, but reject
## samples hidden by walls and distinguish the two moving faces of each leaf.
var world: Node3D
var entries: Array=[]
var sample_count := 0
var door_poses: Dictionary={}
var samples: Dictionary={}
var revision := 0
const DOOR_LAYER := 1 << 18
func setup(game: Node3D) -> void:
	world=game
	var phases: Dictionary={}
	for door in world.doors.values():
		for mesh in door.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null:continue
			var converted:=false
			for s in mesh.mesh.get_surface_count():
				var mat: Material=mesh.get_active_material(s)
				if not mat is StandardMaterial3D or mat.albedo_texture==null or mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
				var lit:=ShaderMaterial.new();lit.shader=preload("res://shaders/door_lit.gdshader")
				lit.set_shader_parameter("base_map",mat.albedo_texture)
				lit.set_shader_parameter("tint",mat.albedo_color)
				lit.set_shader_parameter("roughness_value",mat.roughness)
				lit.set_shader_parameter("metallic_value",mat.metallic)
				lit.set_shader_parameter("specular_value",mat.metallic_specular)
				for role in ["roughness","metallic"]:
					var texture: Texture2D=mat.get(role+"_texture")
					lit.set_shader_parameter("has_"+role,texture!=null)
					if texture!=null:
						lit.set_shader_parameter(role+"_map",texture)
						var channels=[Vector4(1,0,0,0),Vector4(0,1,0,0),Vector4(0,0,1,0),Vector4(0,0,0,1),Vector4(1.0/3,1.0/3,1.0/3,0)]
						lit.set_shader_parameter(role+"_channel",channels[int(mat.get(role+"_texture_channel"))])
				lit.set_shader_parameter("triplanar",mat.uv1_triplanar)
				lit.set_shader_parameter("uv_scale",mat.uv1_scale)
				lit.set_shader_parameter("uv_offset",mat.uv1_offset)
				lit.set_shader_parameter("has_normal",mat.normal_enabled)
				if mat.normal_enabled:lit.set_shader_parameter("normal_map",mat.normal_texture)
				lit.set_shader_parameter("normal_strength",mat.normal_scale)
				mesh.set_surface_override_material(s,lit);converted=true
			if converted:
				# Frame boxes use a whole-mesh override, which takes precedence
				# over surface overrides. All its surfaces were converted above.
				mesh.material_override=null
				# Static room cubemaps have no moving-door visibility. Isolate
				# these receivers from probe reflection masks, retaining live
				# fixture/flashlight diffuse and specular on their own layer.
				preload("res://scripts/render_layers.gd").assign(mesh,DOOR_LAYER)
				var body: Node3D=door
				for leaf in door.leaves:
					if leaf.body.is_ancestor_of(mesh):body=leaf.body;break
				if not phases.has(body):phases[body]=phases.size()%6
				entries.append({"mesh":mesh,"body":body,"door":door,"phase":phases[body],"applied_revision":-1})
		# Use the native opaque leaf as the caster. A thicker invisible box
		# protruded beyond its visible face and shadowed the door itself.
	for light in world.find_children("*","Light3D",true,false):
		if light.get_viewport()!=world.get_viewport():continue
		light.light_cull_mask|=DOOR_LAYER
		light.shadow_caster_mask|=DOOR_LAYER

func advance(force := false) -> void:
	sample_count=0
	var dirty:=force
	for door in world.doors.values():
		if door_poses.get(door,-1.0)!=door.progress:dirty=true
		door_poses[door]=door.progress
	# The bake and opaque physics geometry are static between door moves.
	# Reuse their irradiance until an occluder changes, including on reset.
	if dirty:revision+=1;samples.clear()
	for entry in entries:
		# Keep each body's 10 Hz update, distribute work over six physics
		# steps instead of creating one large periodic CPU spike.
		if not force and world.tick_count%6!=entry.phase:continue
		if entry.applied_revision==revision:continue
		var mesh: MeshInstance3D=entry.mesh
		var point: Vector3=mesh.global_transform*mesh.mesh.get_aabb().get_center()
		if point.distance_squared_to(world.camera.global_position)>144.0:continue
		var axis: Vector3=entry.body.global_basis.z.normalized()
		mesh.set_instance_shader_parameter("door_axis",axis)
		# Offset beyond the panel/frame thickness, never interpolate through it.
		# Multiple surfaces/frame pieces on the same rigid body share a sample.
		# Limit CPU work to nearby leaves, rather than scanning every mesh.
		var key: int=entry.body.get_instance_id()
		if not samples.has(key):
			if entry.body==entry.door:point=entry.door.global_position+Vector3.UP*1.2
			samples[key]=[world.viewmodel_lighting.sample_indirect(point+axis*.24,false),world.viewmodel_lighting.sample_indirect(point-axis*.24,false)]
			sample_count+=2
		var front: Color=samples[key][0]
		var back: Color=samples[key][1]
		mesh.set_instance_shader_parameter("indirect_front",Vector3(front.r,front.g,front.b))
		mesh.set_instance_shader_parameter("indirect_back",Vector3(back.r,back.g,back.b))
		entry.applied_revision=revision

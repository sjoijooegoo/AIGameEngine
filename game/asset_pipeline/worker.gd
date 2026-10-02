extends SceneTree
## Isolated engine worker for real resource inspection, normalization, scene packing and renders.

const Props = preload("res://scripts/props.gd")
var request: Dictionary
var result: Dictionary = {}
var root3d: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--request="):
			path = arg.trim_prefix("--request=")
	request = JSON.parse_string(FileAccess.get_file_as_string(path))
	root3d = Node3D.new()
	root3d.name = "AssetWorker"
	root.add_child(root3d)
	match request.operation:
		"prepare":
			prepare()
		"build":
			build_scene()
		"preview":
			await preview()
	var out := FileAccess.open(request.result, FileAccess.WRITE)
	out.store_string(JSON.stringify(result, "\t"))
	out.close()
	quit(0 if not result.has("error") else 1)

func vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func collect_bounds(node: Node, target: Node3D, items: Array) -> void:
	if node is MeshInstance3D and node.mesh:
		items.append((target.global_transform.affine_inverse() * node.global_transform) * node.mesh.get_aabb())
	for child in node.get_children():
		collect_bounds(child, target, items)

func bounds(node: Node3D) -> AABB:
	var items: Array = []
	collect_bounds(node, node, items)
	var value := AABB()
	for i in range(items.size()):
		value = items[i] if i == 0 else value.merge(items[i])
	return value

func inspect(node: Node, output: Array) -> void:
	if node is MeshInstance3D and node.mesh:
		var surfaces: Array = []
		for index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(index)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var normals = arrays[Mesh.ARRAY_NORMAL]
			var uv = arrays[Mesh.ARRAY_TEX_UV]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var mat: Material = node.get_active_material(index)
			var info := {"vertices": vertices.size(), "normals": normals.size() if normals != null else 0, "uv": uv.size() if uv != null else 0, "triangles": int((indices.size() if indices != null and indices.size() > 0 else vertices.size()) / 3), "material": mat.resource_name if mat else "MISSING", "material_type": mat.get_class() if mat else "MISSING", "textures": {}}
			if mat is BaseMaterial3D:
				info.roughness = mat.roughness
				info.metallic = mat.metallic
				for role in ["albedo", "normal", "roughness", "metallic", "ao", "emission"]:
					var texture = mat.get(role + "_texture")
					if texture is Texture2D:
						info.textures[role] = {"path": texture.resource_path, "width": texture.get_width(), "height": texture.get_height()}
			surfaces.append(info)
		output.append({"name": str(node.name), "surfaces": surfaces})
	for child in node.get_children():
		inspect(child, output)

func rig_info(node: Node, output: Dictionary) -> void:
	if node is Skeleton3D:
		output.skeletons.append({"name": str(node.name), "bones": node.get_bone_count()})
	if node is AnimationPlayer:
		for clip in node.get_animation_list():
			output.animations.append({"name": str(clip), "duration": node.get_animation(clip).length})
	for child in node.get_children():
		rig_info(child, output)

func apply_materials(node: Node, roles: Dictionary) -> void:
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var previous: Material = node.get_active_material(i)
			var mat: StandardMaterial3D = previous.duplicate() if previous is StandardMaterial3D else StandardMaterial3D.new()
			for role in roles:
				mat.set(role + "_texture", load(roles[role]))
				if role in ["normal", "ao", "emission"]:
					mat.set(role + "_enabled", true)
			node.set_surface_override_material(i, mat)
	for child in node.get_children():
		apply_materials(child, roles)

func own_children(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		# Fully pack the hierarchy. Retaining instance paths while re-owning their
		# children produces inherited duplicates when the prepared scene reloads.
		child.scene_file_path = ""
		child.owner = owner_node
		own_children(child, owner_node)

func prepare() -> void:
	var source = load(request.source)
	if not source is PackedScene:
		result.error = "Imported file is not a 3D scene"
		return
	var wrapper := Node3D.new()
	wrapper.name = "PreparedAsset"
	root3d.add_child(wrapper)
	var conversion := Node3D.new()
	conversion.name = "Conversion"
	conversion.scale = Vector3.ONE * float(request.unit_scale)
	conversion.rotation_degrees.y = float(request.yaw_degrees)
	wrapper.add_child(conversion)
	var model: Node3D = source.instantiate()
	conversion.add_child(model)
	var before := bounds(wrapper)
	# Parent correction preserves rig hierarchy and animation tracks.
	conversion.position = Vector3(-before.get_center().x, -before.position.y, -before.get_center().z)
	if not request.get("textures", {}).is_empty():
		apply_materials(model, request.textures)
	var box := bounds(wrapper)
	if box.size.length() < 0.00001:
		result.error = "Imported model contains no usable mesh bounds"
		return
	var meshes: Array = []
	inspect(model, meshes)
	var rig := {"skeletons": [], "animations": []}
	rig_info(model, rig)
	own_children(wrapper, wrapper)
	var scene := PackedScene.new()
	scene.pack(wrapper)
	if ResourceSaver.save(scene, request.output) != OK:
		result.error = "Unable to save prepared scene"
		return
	result = {"size_m": arr(box.size), "bounds_min": arr(box.position), "meshes": meshes, "rig": rig, "anchors": {"floor": [0, 0, 0], "top": [0, box.size.y, 0], "center": [0, box.size.y / 2, 0]}, "scene": request.output}

func lighting(parent: Node3D) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("263b4c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dce5ef")
	env.ambient_light_energy = 0.25
	environment.environment = env
	parent.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	parent.add_child(sun)
	if request.get("lighting", "neutral") == "dark":
		env.ambient_light_energy = 0.08
		sun.light_energy = 0.16
	elif request.get("lighting", "neutral") == "raking":
		env.ambient_light_energy = 0.15
		sun.rotation_degrees = Vector3(-12, -65, 0)
		sun.light_energy = 0.85

func add_collision(parent: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = size.y / 2
	body.add_child(collision)

func build_scene() -> void:
	var plan: Dictionary = request.plan
	var room := Node3D.new()
	room.name = "AssembledRoom"
	room.set_script(load("res://asset_pipeline/scene_runtime.gd"))
	room.set("spawn", vec(plan.spawn))
	room.set("room_size", vec(plan.room))
	room.set("exit_point", vec(plan.exit))
	room.set("building", true)
	root3d.add_child(room)
	lighting(room)
	var size := vec(plan.room)
	var floor_mat := Props.material(Color("879799"), 0.85)
	Props.box(room, "Floor", Vector3(size.x, 0.2, size.z + 4), Vector3(0, -0.1, -1), floor_mat, true)
	var wall_mat := Props.material(Color("536d78"), 0.9)
	Props.box(room, "SouthWall", Vector3(size.x, size.y, 0.15), Vector3(0, size.y/2, size.z/2), wall_mat, true)
	Props.box(room, "WestWall", Vector3(0.15, size.y, size.z), Vector3(-size.x/2, size.y/2, 0), wall_mat, true)
	Props.box(room, "EastWall", Vector3(0.15, size.y, size.z), Vector3(size.x/2, size.y/2, 0), wall_mat, true)
	var portal: Dictionary = plan.portal
	var left_end := float(portal.x) - float(portal.width)/2
	var right_start := float(portal.x) + float(portal.width)/2
	Props.box(room, "NorthLeft", Vector3(left_end + size.x/2, size.y, 0.15), Vector3((-size.x/2 + left_end)/2, size.y/2, -size.z/2), wall_mat, true)
	Props.box(room, "NorthRight", Vector3(size.x/2-right_start, size.y, 0.15), Vector3((size.x/2+right_start)/2, size.y/2, -size.z/2), wall_mat, true)
	for item in plan.entities:
		var group := Node3D.new()
		group.name = item.id
		group.position = vec(item.position)
		group.rotation_degrees.y = float(item.yaw)
		room.add_child(group)
		var packed: PackedScene = load(item.scene)
		var model := packed.instantiate()
		group.add_child(model)
		var dimensions := vec(item.size)
		if item.get("behavior", "") == "door":
			group.position.x -= dimensions.x/2
			model.position.x = dimensions.x/2
			group.set_meta("door", true)
			var collider_root := Node3D.new()
			collider_root.position.x = dimensions.x/2
			group.add_child(collider_root)
			add_collision(collider_root, dimensions)
		else:
			add_collision(group, dimensions)
		group.set_meta("asset_id", item.asset)
		group.set_meta("revision", item.revision)
	room.set("building", false)
	own_children(room, room)
	var scene := PackedScene.new()
	scene.pack(room)
	var error := ResourceSaver.save(scene, request.output)
	result = {"scene": request.output, "entities": plan.entities.size(), "error_code": error}
	if error != OK:
		result.error = "Unable to save assembled scene"

func preview() -> void:
	var packed: PackedScene = load(request.source)
	var model: Node3D = packed.instantiate()
	root3d.add_child(model)
	if request.kind == "scene":
		model.testing = true
	if request.kind == "asset":
		lighting(root3d)
		var box := bounds(model)
		var extent := maxf(box.size.x, box.size.z) * 3
		Props.box(root3d, "Stage", Vector3(extent, 0.02, extent), Vector3(0, -0.02, 0), Props.material(Color("647984")))
	var box := bounds(model)
	var camera := Camera3D.new()
	camera.fov = 48
	camera.near = 0.01
	root3d.add_child(camera)
	camera.current = true
	var center := box.get_center()
	var distance := maxf(0.4, box.size.length() * 1.5)
	var captures: Array = []
	var directions := {"front": Vector3(0, 0.35, -1), "back": Vector3(0, 0.35, 1), "side": Vector3(1, 0.35, 0), "overview": Vector3(1, 0.9, 1)}
	if request.kind == "scene":
		directions = {"overview": Vector3(0.8, 1.2, 1), "reverse": Vector3(-0.8, 1.2, -1)}
	for view in directions:
		camera.position = center + directions[view].normalized() * distance
		camera.look_at(center)
		await process_frame
		await RenderingServer.frame_post_draw
		var path := str(request.directory).path_join(view + ".png")
		root.get_texture().get_image().save_png(path)
		captures.append({"view": view, "path": path, "camera": arr(camera.position)})
	if request.kind == "scene":
		camera.position = model.spawn + Vector3(0, 1.6, 0)
		camera.look_at(Vector3(model.spawn.x, 1.6, -float(model.room_size.z)/2))
		await process_frame
		await RenderingServer.frame_post_draw
		var path := str(request.directory).path_join("player.png")
		root.get_texture().get_image().save_png(path)
		captures.append({"view": "player", "path": path, "camera": arr(camera.position)})
	result = {"captures": captures, "bounds": {"min": arr(box.position), "size": arr(box.size)}, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name()}

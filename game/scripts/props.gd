extends RefCounted
## Shared, inspectable sample assets. Replace these with imported production assets.

static func material(color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

static func mesh(parent: Node3D, id: String, shape: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = shape
	node.position = pos
	node.material_override = mat
	parent.add_child(node)
	return node

static func box(parent: Node3D, id: String, size: Vector3, pos: Vector3, mat: Material, solid: bool = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = id
	root.position = pos
	parent.add_child(root)
	var shape := BoxMesh.new()
	shape.size = size
	mesh(root, "Mesh", shape, Vector3.ZERO, mat)
	if solid:
		var collision := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		root.add_child(collision)
	return root

static func mannequin(parent: Node3D, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	parent.add_child(root)
	var cloth := material(color)
	var dark := material(Color("263445"))
	box(root, "Torso", Vector3(0.55, 0.7, 0.3), Vector3(0, 1.1, 0), cloth)
	var head := SphereMesh.new()
	head.radius = 0.20
	head.height = 0.40
	head.radial_segments = 16
	head.rings = 8
	mesh(root, "Head", head, Vector3(0, 1.66, 0), material(Color("d9b898")))
	for side in [-1, 1]:
		box(root, "Leg%s" % side, Vector3(0.20, 0.7, 0.24), Vector3(side * 0.17, 0.38, 0), dark)
		box(root, "Arm%s" % side, Vector3(0.16, 0.65, 0.20), Vector3(side * 0.38, 1.1, 0), cloth)
	box(root, "Badge", Vector3(0.12, 0.08, 0.02), Vector3(-0.12, 1.28, -0.16), material(Color("efbc62")))
	return root

extends Node3D
## Swept doors, explicit offset pockets for sliding panels, and occupancy protection.
var definition: Dictionary
var leaves: Array = []
var progress := 0.0
var target := 0.0
var swing := 1.0
var blocked := false
var mode := "hinge"
var area: Area3D
var blocker: Dictionary = {}

# JSON still owns the asset catalogue, but these explicit references keep the
# animated door scenes in exported PCKs. Editor-only dynamic loads can hide
# this dependency during development.
const DOOR_SCENES: Dictionary = {
	"wood_door": preload("res://assets/library/l4d2.bank.doormain01_static/ffcedeabada80bde/prepared.tscn"),
	"glass_door": preload("res://assets/library/l4d2.bank.doorglassmain01_static/626ecfd920b160e2/prepared.tscn"),
	"fire_door": preload("res://assets/library/l4d2.bank.doormainmetalsmall01_baked/269a77c30e5ebcb2/prepared.tscn"),
	"vision_door": preload("res://assets/library/l4d2.bank.refine.doormainmetalwindow01/e596982429902351/prepared.tscn"),
	"garden_gate": preload("res://assets/library/l4d2.bank.refine.gate_wall_gate003_64/7684c63fe0269077/prepared.tscn"),
	"shutter_curtain": preload("res://assets/library/l4d2.bank.refine.shutter_curtain/a1b17966eab47005/prepared.tscn"),
	"shutter_housing": preload("res://assets/library/l4d2.bank.refine.shutter_housing/3039416b1c4061c5/prepared.tscn")
}

func setup(d: Dictionary, base: float, pins: Dictionary, finishes: Dictionary) -> void:
	definition = d.duplicate(true)
	swing = float(d.get("hinge_swing",1))
	position = Vector3(d.x,base,d.z)
	rotation.y = 0 if d.axis=="x" else -PI/2
	# The compact original airlock has no physical pockets; solid security leaves hinge.
	mode = "lift" if d.type=="shutter" else "slide" if d.type=="elevator" else "hinge"
	var width: float = d.w-.13
	var height: float = d.h-.03
	# Wide openings use practical double leaves rather than a four-metre swing.
	var paired: bool = mode=="hinge" and d.w>=1.9
	# Four telescoping leaves fit the 2.8m-wide elevator car without side-wall pockets.
	var parts := 4 if mode=="slide" else 2 if paired else 1
	for i in range(parts):
		var local_width := width/parts
		var pivot := Node3D.new()
		pivot.position.x = (-width/2 if i==0 else width/2) if mode=="hinge" else 0.0
		pivot.position.z = -.05*swing if mode=="hinge" else 0.0
		add_child(pivot)
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		pivot.add_child(body)
		var center_x: float = (local_width/2 if i==0 else -local_width/2) if mode=="hinge" else (float(i)-1.5)*local_width if mode=="slide" else 0.0
		var shape := BoxShape3D.new()
		shape.size = Vector3(local_width,height-.06,.075)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(center_x,height/2+.01,0)
		body.add_child(col)
		var key := "wood_door" if d.type=="wood" else "glass_door" if d.type=="glass" else ("vision_door" if d.id=="f4_gate" else "garden_gate") if d.type=="bars" else "shutter_curtain" if d.type=="shutter" else "fire_door"
		var pin: Dictionary = pins[key]
		var door_scene: PackedScene = DOOR_SCENES.get(key) as PackedScene
		if door_scene==null:door_scene=load(pin.resource) as PackedScene
		var mesh: Node3D
		if door_scene!=null:
			mesh=door_scene.instantiate() as Node3D
		else:
			# Keep a visible, collidable panel if an optional imported door scene
			# is unavailable in an export. The explicit preload normally prevents
			# this path; it avoids an invisible doorway as a last-resort fallback.
			push_warning("Door asset unavailable in export: "+key)
			var fallback:=MeshInstance3D.new()
			var fallback_mesh:=BoxMesh.new()
			fallback_mesh.size=Vector3(local_width,height,.075)
			fallback.mesh=fallback_mesh
			fallback.material_override=finishes.metal if key in ["fire_door","vision_door"] else finishes.wood
			mesh=fallback
		# Measured projecting hardware of both metal leaves is on native +X.
		# Left jamb hinges therefore use native yaw 0; right leaves reverse it.
		var width_x: bool = key in ["fire_door","vision_door"]
		mesh.rotation.y = (0.0 if i==0 else PI) if width_x else (-PI/2 if i==0 else PI/2)
		mesh.scale = Vector3(local_width/pin.size[0],height/pin.size[1],.10/pin.size[2]) if width_x else Vector3(.10/pin.size[0],height/pin.size[1],local_width/pin.size[2])
		mesh.position = Vector3(center_x,.01,0)
		if mode=="slide":
			# Functional elevator architecture: plain steel telescoping panels have no knobs.
			mesh.free()
			mesh = MeshInstance3D.new()
			var panel := BoxMesh.new()
			panel.size = Vector3(local_width-.002,height,.08)
			mesh.mesh = panel
			mesh.material_override = finishes.metal
			mesh.position = Vector3(center_x,height/2+.01,0)
			body.add_child(mesh)
		else:
			# Hinge and lift leaves keep their imported model. They still need to
			# live under the moving body so the visual follows the collision shape.
			body.add_child(mesh)
			apply_dark_room_finish(mesh,key)
		if mode=="lift":apply_curtain_finish(mesh,base+height+.01)
		if d.type=="glass":
			var glazing := MeshInstance3D.new()
			var pane := BoxMesh.new();pane.size=Vector3(local_width*.82,height*.76,.006)
			glazing.mesh=pane;glazing.position=Vector3(center_x,height*.58,0)
			glazing.material_override=finishes.glass
			body.add_child(glazing)
		var depth := (-.22 if i in [0,3] else -.34) if mode=="slide" else -.04 if mode=="lift" else .05*swing
		body.position.z = depth
		var slide_distance := (.43 if i in [0,3] else .43+local_width)*(1 if i>=2 else -1)
		leaves.append({"pivot":pivot,"body":body,"shape":shape,"col":col,"mesh":mesh,"mesh_scale":mesh.scale,"closed_shape":shape.size,"closed_col":col.position,"center_x":center_x,"depth":depth,"side":1.0 if i==0 else -1.0,"width":local_width,"slide_distance":slide_distance})
	area = Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var interaction := CollisionShape3D.new()
	var interaction_box := BoxShape3D.new()
	interaction_box.size = Vector3(d.w,d.h,.08)
	interaction.shape = interaction_box
	interaction.position.y = d.h/2
	area.add_child(interaction)
	add_child(area)
	# Seven millimetres of side clearance accommodates the hinge offset's
	# initial corner sweep (about 3mm) plus the 2mm physics query margin.
	# Their faces sit 30mm ahead of the wall faces rather than sharing a depth plane.
	var frame_material: Material = finishes.wood if d.type=="wood" else finishes.metal
	if mode=="lift":
		# The native tracks and roller stay fixed. Only the 18-face curtain moves.
		var housing_pin: Dictionary=pins.shutter_housing
		var curtain_pin: Dictionary=pins.shutter_curtain
		var housing := (DOOR_SCENES["shutter_housing"] as PackedScene).instantiate() as Node3D
		housing.rotation.y=-PI/2
		var sx: float=.10/curtain_pin.size[0]
		var sy: float=height/curtain_pin.size[1]
		var sz: float=width/curtain_pin.size[2]
		housing.scale=Vector3(sx,sy,sz)
		# Source centres: curtain X=-.080283, housing X=.053743.
		housing.position=Vector3(-.00149*sz,.001273*sy+.01,-.04+.134026*sx)
		add_child(housing)
		# Track collars overlap the curtain edges visually; their outer supports
		# have collision outside the moving aperture.
		for x in [-float(d.w)/2-.015,float(d.w)/2+.015]:
			make_frame(Vector3(.10,d.h,.34),Vector3(x,float(d.h)/2,.045),frame_material)
	else:
		for x in [-float(d.w)/2+.029,float(d.w)/2-.029]:
			make_frame(Vector3(.058,d.h,.26),Vector3(x,float(d.h)/2,0),frame_material)
		make_frame(Vector3(d.w+.08,.07,.26),Vector3(0,float(d.h)+.02,0),frame_material)
	var sign := Label3D.new()
	sign.text = d.label
	sign.font_size = 34
	sign.pixel_size = .007
	sign.modulate = Color("d0d2bd")
	sign.position.y = d.h+.23
	add_child(sign)

func owns(collider: Object) -> bool:
	if collider==area:return true
	for leaf in leaves:
		if collider==leaf.body:return true
	return false

func apply_dark_room_finish(root_node: Node, key: String) -> void:
	# Doors are animated and therefore cannot use the architectural lightmap.
	# Keep their imported maps, but bring diffuse response closer to the baked
	# wall/floor values so an unlit closed door does not read as a bright card.
	var factor: float = {"fire_door":.68,"wood_door":.72,"glass_door":.78,"vision_door":.72,"garden_gate":.82}.get(key,1.0)
	if factor>=.99:return
	var meshes: Array=[root_node]
	meshes.append_array(root_node.find_children("*","MeshInstance3D",true,false))
	for item in meshes:
		if not item is MeshInstance3D:continue
		var mesh: MeshInstance3D=item
		for surface in mesh.mesh.get_surface_count():
			var source:=mesh.get_active_material(surface)
			if not source is StandardMaterial3D:continue
			var tuned:=source.duplicate() as StandardMaterial3D
			var c:=tuned.albedo_color
			tuned.albedo_color=Color(c.r*factor,c.g*factor,c.b*factor,c.a)
			tuned.roughness=clampf(tuned.roughness+.06,.0,1.0)
			mesh.set_surface_override_material(surface,tuned)

func apply_curtain_finish(node: Node, roller_height: float) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var original: BaseMaterial3D=node.get_active_material(i) as BaseMaterial3D
			assert(original and original.albedo_texture,"Curtain must retain its native albedo")
			var finish:=ShaderMaterial.new()
			finish.shader=preload("res://shaders/shutter_curtain.gdshader")
			finish.set_shader_parameter("albedo_texture",original.albedo_texture)
			finish.set_shader_parameter("roller_height",roller_height)
			node.set_surface_override_material(i,finish)
	for child in node.get_children():apply_curtain_finish(child,roller_height)

func make_frame(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new();box.size=size
	mesh.mesh=box;mesh.material_override=material;mesh.position=at
	add_child(mesh)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new();shape.size=size
	col.shape=shape;body.add_child(col);mesh.add_child(body)

func toggle(_player_position: Vector3) -> void:
	if target>.5:
		target = 0.0
	else:
		target = 1.0

func leaf_transform(leaf: Dictionary, value: float) -> Transform3D:
	var t: Transform3D = leaf.pivot.transform
	var b := Transform3D(Basis.IDENTITY,Vector3(0,0,leaf.depth))
	if mode=="hinge":
		t.basis = Basis(Vector3.UP,value*PI/2*swing*leaf.side)
	elif mode=="lift":
		b.origin.y = value*(definition.h-.18)
	else:
		b.origin.x = value*leaf.slide_distance
	return global_transform*t*b

func advance(dt: float) -> void:
	if abs(progress-target)<.001:return
	var next := move_toward(progress,target,dt*.80)
	var exclude: Array[RID] = []
	for leaf in leaves:exclude.append(leaf.body.get_rid())
	blocked = false
	blocker = {}
	# Four subdivisions bound sweep motion before any mutation, including both leaves.
	for sample in range(1,5):
		var fraction := lerpf(progress,next,float(sample)/4)
		for leaf in leaves:
			var query := PhysicsShapeQueryParameters3D.new()
			var collision_transform: Transform3D = leaf.col.transform
			query.shape = leaf.shape
			if mode=="lift":
				var factor: float = lerpf(1.0,.15/float(definition.h),fraction)
				var reduced := BoxShape3D.new()
				reduced.size = Vector3(leaf.closed_shape.x,leaf.closed_shape.y*factor,leaf.closed_shape.z)
				query.shape = reduced
				collision_transform.origin.y = leaf.closed_col.y*factor
			query.transform = leaf_transform(leaf,fraction)*collision_transform
			query.exclude = exclude
			query.collision_mask = 11
			query.margin = .002
			var hits := get_world_3d().direct_space_state.intersect_shape(query,1)
			if not hits.is_empty():
				blocked = true
				var hit: Node3D = hits[0].collider
				blocker = {"node":str(hit.get_path()),"position":[hit.global_position.x,hit.global_position.y,hit.global_position.z]}
				return
	progress = next
	apply_progress()

func apply_progress() -> void:
	for leaf in leaves:
		if mode=="hinge":leaf.pivot.rotation.y = progress*PI/2*swing*leaf.side
		elif mode=="lift":
			var factor: float = lerpf(1.0,.15/float(definition.h),progress)
			leaf.body.position.y = progress*(definition.h-.18)
			# Rigid slats move into the fixed roller housing. Clip the hidden upper
			# section instead of shrinking the mesh and squeezing its texture.
			leaf.mesh.scale = leaf.mesh_scale
			leaf.shape.size = Vector3(leaf.closed_shape.x,leaf.closed_shape.y*factor,leaf.closed_shape.z)
			leaf.col.position.y = leaf.closed_col.y*factor
		else:leaf.body.position.x = progress*leaf.slide_distance

func reset_closed() -> void:
	progress=0;target=0;swing=float(definition.get("hinge_swing",1));blocked=false
	for leaf in leaves:
		leaf.pivot.rotation.y=0
		leaf.body.position=Vector3(0,0,leaf.depth)
		leaf.mesh.scale=leaf.mesh_scale
		leaf.shape.size=leaf.closed_shape
		leaf.col.position=leaf.closed_col

func state() -> Dictionary:
	var rotations := []
	for leaf in leaves:rotations.append(leaf.pivot.rotation.y)
	return {"angle":progress*PI/2,"target":target*PI/2,"progress":progress,"hinge_swing":swing,"leaf_rotations":rotations,"blocked":blocked,"blocker":blocker,"mode":mode,"leaves":leaves.size(),"position":[position.x,position.y,position.z]}

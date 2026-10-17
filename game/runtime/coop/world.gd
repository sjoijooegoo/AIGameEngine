extends Node3D
## Bank structural slice from the current bank layout, shared by both peers.
## All collision shapes are built from data, independent of render meshes/assets.
var visual := true
var materials: Dictionary={}
var collision_count := 0

func _ready() -> void:
	var colors:={"wall":"949f9c","wallgreen":"7b8e84","wallwood":"76634a","concrete":"858c8d","tile":"bdc4bf","office":"76838c","lino":"8a978e","wood":"8b7355","woodlight":"9e8667","kitchen":"a0aaa5","ceil":"b6bfb9","metal":"647682","asphalt":"666a69","grate":"576474","stairs":"939f9b","glass":"789da2"}
	for key in colors:
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color(colors[key]);mat.roughness=.85;materials[key]=mat
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://coop/bank_layout.json"))
	for level in spec.levels:build_level(level)
	if visual:
		var environment:=WorldEnvironment.new();var settings:=Environment.new()
		settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("364755")
		settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color("d8e4ed");settings.ambient_light_energy=.65
		settings.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment.environment=settings;add_child(environment)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-65,-30,0);sun.light_energy=.7;add_child(sun)
		for floor in range(4):
			for point in [Vector2(9,12),Vector2(22,17),Vector2(30,12),Vector2(22,5)]:
				var lamp:=OmniLight3D.new();lamp.position=Vector3(point.x,2.9+floor*3.6,point.y);lamp.omni_range=12;lamp.light_energy=1.3;add_child(lamp)
	print("COOP_WORLD collisions=",collision_count," visual=",visual)

func box_at(size: Vector3, pos: Vector3, mat: Material, collision:=true, parent: Node3D=self) -> MeshInstance3D:
	if collision:
		var body:=StaticBody3D.new();body.position=pos
		var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape
		body.add_child(collider);parent.add_child(body);collision_count+=1
	if not visual:return null
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.position=pos;mesh.material_override=mat;parent.add_child(mesh);return mesh

func build_door(definition: Dictionary, base: float) -> void:
	# Closed, static doors in the movement-only protocol. Both peers agree.
	var size:=Vector3(float(definition.w),float(definition.h),.075)
	if definition.axis!="x":size=Vector3(.075,float(definition.h),float(definition.w))
	box_at(size,Vector3(definition.x,base+float(definition.h)/2,definition.z),materials.metal)

func rectangle(r: Dictionary, base: float, low: float, high: float, material: Material, collision := true) -> void:
	var size := Vector3(abs(r.x1-r.x0),high-low,abs(r.z1-r.z0))
	if size.x < 0.005 or size.y < 0.005 or size.z < 0.005:
		return
	box_at(size,Vector3((r.x0+r.x1)/2,base+(low+high)/2,(r.z0+r.z1)/2),material,collision)

func build_level(level: Dictionary) -> void:
	var base: float = level.base
	for floor_rect in level.floors:
		rectangle(floor_rect,base,float(floor_rect.y)-0.15,float(floor_rect.y),materials.get(floor_rect.material,materials.tile))
	for ceil_rect in level.ceilings:
		rectangle(ceil_rect,base,float(ceil_rect.h),float(ceil_rect.h)+0.15,materials.ceil)
	for wall in level.walls:
		build_wall(wall,base)
	for r in level.boxes:
		# Original structural divider, stair landing and toilet partitions.
		var top: float = 3.59 if is_equal_approx(float(r.y1),3.6) else float(r.y1)
		rectangle(r,base,float(r.y0),top,materials.get(r.material if r.material is String else "metal",materials.concrete),bool(r.collision) or float(r.y1)-float(r.y0)>0.1)
	for flight in level.stairs:
		build_flight(flight,base)
	for definition in level.doors:
		build_door(definition,base)
	# Cab lining covers the room's plaster back and side walls. The native
	# trim contributes handrails and the roof, with no rail across the entrance.
	var back_z: float=5.1 if level.id=="G" else 5.6
	box_at(Vector3(2.78,3.02,.025),Vector3(38.5,base+1.51,back_z+.016),materials.metal)
	for x in [37.116,39.884]:
		box_at(Vector3(.025,3.02,8.89-back_z),Vector3(x,base+1.51,(8.89+back_z)/2),materials.metal)

func build_wall(wall: Dictionary, base: float) -> void:
	var vert: bool = abs(float(wall.x1)-float(wall.x0)) < 0.001
	var lo: float = min(wall.z0,wall.z1) if vert else min(wall.x0,wall.x1)
	var hi: float = max(wall.z0,wall.z1) if vert else max(wall.x0,wall.x1)
	var constant: float = wall.x0 if vert else wall.z0
	var thickness: float = wall.get("t",0.2)
	# Source walls ended exactly on the next floor's top face. Keep their caps
	# inside the 0.15m slab, avoiding coplanar draw surfaces and visible flicker.
	var height: float = min(float(wall.get("h",3.6)),3.59)
	var material: Material = materials.get(wall.get("m","wall"),materials.wall)
	var gaps: Array = wall.get("gaps",[]).duplicate()
	gaps.sort_custom(func(a,b):return a[0]<b[0])
	var pieces: Array = []
	var cursor := lo
	for gap in gaps:
		if gap[0]>cursor:
			pieces.append([cursor,float(gap[0]),0.0,height])
		if not wall.get("noLintel",false):
			pieces.append([float(gap[0]),float(gap[1]),float(wall.get("gapH",2.25)),height])
		cursor = max(cursor,float(gap[1]))
	if cursor<hi:
		pieces.append([cursor,hi,0.0,height])
	for p in pieces:
		if wall.get("glass",false):
			for band in [[0.0,1.05,material],[2.6,height,material]]:
				var sz := Vector3(thickness,band[1]-band[0],p[1]-p[0]) if vert else Vector3(p[1]-p[0],band[1]-band[0],thickness)
				var pos := Vector3(constant,base+(band[0]+band[1])/2,(p[0]+p[1])/2) if vert else Vector3((p[0]+p[1])/2,base+(band[0]+band[1])/2,constant)
				box_at(sz,pos,band[2])
			# Laminated teller glazing is 16mm thick. Separate textured mullions
			# provide a readable enclosure and close all pane/frame interfaces.
			var count: int = maxi(1,ceili((p[1]-p[0])/1.55))
			var span: float = (p[1]-p[0])/count
			for i in range(count):
				var along: float = p[0]+span*(i+.5)
				var pane_size := Vector3(.016,1.48,span-.04) if vert else Vector3(span-.04,1.48,.016)
				var pane_at := Vector3(constant,base+1.825,along) if vert else Vector3(along,base+1.825,constant)
				box_at(pane_size,pane_at,materials.glass)
			for i in range(count+1):
				var along: float=p[0]+span*i
				var at:=Vector3(constant,base+1.825,along) if vert else Vector3(along,base+1.825,constant)
				box_at(Vector3(.07,1.55,.07),at,materials.metal)
			for rail_y in [1.07,2.58]:
				var rail_size:=Vector3(.07,.07,p[1]-p[0]) if vert else Vector3(p[1]-p[0],.07,.07)
				var rail_at:=Vector3(constant,base+rail_y,(p[0]+p[1])/2) if vert else Vector3((p[0]+p[1])/2,base+rail_y,constant)
				box_at(rail_size,rail_at,materials.metal)
		else:
			var sz := Vector3(thickness,p[3]-p[2],p[1]-p[0]) if vert else Vector3(p[1]-p[0],p[3]-p[2],thickness)
			var pos := Vector3(constant,base+(p[2]+p[3])/2,(p[0]+p[1])/2) if vert else Vector3((p[0]+p[1])/2,base+(p[2]+p[3])/2,constant)
			if sz.x>0.01 and sz.z>0.01:
				if materials.has("lower_wall") and wall.get("m","wall") in ["wall","wallgreen"] and p[2]<1.15:
					var split: float = min(1.15,p[3])
					var lower_sz := sz
					lower_sz.y = split-p[2]
					var lower_pos := pos
					lower_pos.y = base+(split+p[2])/2
					box_at(lower_sz,lower_pos,materials.lower_wall)
					if p[3]>split:
						var upper_sz := sz
						upper_sz.y = p[3]-split
						var upper_pos := pos
						upper_pos.y = base+(p[3]+split)/2
						box_at(upper_sz,upper_pos,material)
				else:
					box_at(sz,pos,material)

func build_flight(flight: Dictionary, base: float) -> void:
	var xa: float = flight.xa
	var xb: float = flight.xb
	var za: float = flight.za
	var zb: float = flight.zb
	var ya: float = flight.y0+base
	var yb: float = flight.y1+base
	for i in range(12):
		var z0 := lerpf(za,zb,float(i)/12)
		var z1 := lerpf(za,zb,float(i+1)/12)
		var top := lerpf(ya,yb,float(i+1)/12)
		box_at(Vector3(xb-xa,0.18,abs(z1-z0)),Vector3((xa+xb)/2,top-0.09,(z0+z1)/2),materials.stairs,false)
	# Continuous ramp contact prevents capsule snagging on visual risers.
	var points := PackedVector3Array()
	for x in [xa,xb]:
		for pair in [[za,ya],[zb,yb]]:
			points.append(Vector3(x,pair[1],pair[0]))
			points.append(Vector3(x,pair[1]-0.24,pair[0]))
	var body := StaticBody3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)

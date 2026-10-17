extends Node3D
## Original map encounter preview. Quests and lock progression remain separate.

var spec: Dictionary
var dressing: Dictionary
var lighting: Dictionary
var held_weapon: SubViewportContainer
var player: CharacterBody3D
var camera: Camera3D
var camera_motion=preload("res://scripts/camera_motion.gd").new()
var frozen_presentation := false
var doors: Dictionary = {}
var materials: Dictionary = {}
var fixture_materials: Dictionary = {}
var viewmodel_lighting=preload("res://scripts/viewmodel_lighting.gd").new()
var flashlight_lighting=preload("res://scripts/flashlight_lighting.gd").new()
var door_lighting=preload("res://scripts/door_lighting.gd").new()
var occlusion_vertices := PackedVector3Array()
var static_boxes: Array=[]
var static_batch_stats: Dictionary={}
var static_prop_stats: Dictionary={}
var indoor_lights=preload("res://scripts/indoor_lights.gd").new()
var reflections=preload("res://scripts/bank_reflections.gd").new()
var indirect_stats: Dictionary={}
var testing := false
var profiler=preload("res://addons/ai_engine/performance/monitor.gd").new()
var tick_count := 0
var weapon_wall_filtered := 10.0
var pitch := 0.0
## Keep the source spawn position; face its nearest exit so the first view
## introduces the bank door and a readable route rather than a desk dead end.
var fixtures: Dictionary = {"default":[23,0.04,8.2,-1.120596],"hall":[16,0.04,18,0],"yard":[20,0.04,-7,0],"front_stairs":[35.5,0.04,16,PI],"front_top_base":[35.5,7.24,16,PI],"back_stairs":[4.5,0.04,3.5,PI],"floor2":[18,3.64,12,0],"floor3":[18,7.24,11,0],"floor4":[22,10.84,11,0]}
var ui: CanvasLayer
var flashlight: SpotLight3D
var held_actions: Dictionary = {}
var door_design: Dictionary
var infected_data: Dictionary
var infected_profiles: Dictionary
var infected: Array = []
var infected_audio=preload("res://scripts/infected_audio.gd").new()
var crowd=preload("res://scripts/infected_crowd.gd").new()
var navigation = preload("res://scripts/infected_navigation.gd").new()
var infected_ready := false
var current_fixture := "default"
var player_hp := 100.0
var player_dead := false
var kills := 0
var hurt_cooldown := 0.0
var strike_cooldown := 0.0
var strike_time := -1.0
var strike_kind := "hit"
var strike_applied := false
var last_combat_event := ""
var damage_overlay: ColorRect
var firearms=preload("res://scripts/firearms.gd").new()
var feedback=preload("res://scripts/combat_feedback.gd").new()
var damage_material: ShaderMaterial
var tick_cost_usec := 0
var peak_tick_cost_usec := 0

func _ready() -> void:
	# Resolve automation before loading UI preferences.
	for arg in OS.get_cmdline_user_args():
		if OS.is_debug_build() and (arg.begins_with("--ai-session=") or arg=="--performance-benchmark"):testing=true
		if OS.is_debug_build() and arg.begins_with("--ai-session="):frozen_presentation=true
	add_child(profiler)
	spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/origin_structure.json"))
	dressing = JSON.parse_string(FileAccess.get_file_as_string("res://data/dressing.json"))
	lighting = JSON.parse_string(FileAccess.get_file_as_string("res://data/lighting.json"))
	door_design = JSON.parse_string(FileAccess.get_file_as_string("res://data/door_design.json"))
	infected_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/infected.json"))
	infected_profiles = JSON.parse_string(FileAccess.get_file_as_string("res://data/infected_archetypes.json"))
	fixtures["ui_title"]=fixtures["default"].duplicate()
	for type_key in infected_profiles:
		for scenario in ["pose","attack","chase","combat"]:fixtures["archetype_"+type_key+"_"+scenario]=[20,.04,-7,0]
	fixtures.merge({"audio_near":[20,.04,-7,0],"audio_far":[20,.04,-2,0],"audio_left":[20,.04,-7,-PI/2],"audio_right":[20,.04,-7,PI/2],"audio_wall":[31,.04,6.85,0]})
	fixtures.merge({"infected_chase":[20,.04,-7,0],"infected_combat":[20,.04,-7,0],"infected_wall":[31,.04,6.85,0],"infected_stairs":[35.5,1.29,19.5,0],"infected_showcase":[25,.04,-5,0]})
	fixtures.merge({"torch_default":[23,.04,8.2,-1.120596],"firearms_range":[20,.04,-7,0],"firearms_target":[20,.04,-7,0],"firearms_wall":[31,.04,6.85,0],"firearms_close":[20,.04,-7,0]})
	fixtures.merge({"baton_range":[20,.04,-7,0],"baton_target":[20,.04,-7,0],"baton_far":[20,.04,-7,0],"baton_behind":[20,.04,-7,PI],"baton_wall":[31,.04,5.5,0],"baton_crowd":[20,.04,-7,0],"baton_kill":[20,.04,-7,0]})
	fixtures.merge({"blood_target":[20,.04,-7,0],"blood_wall":[20,.04,-10.7,0]})
	fixtures.merge({"combat_reaction_front":[20,.04,-7,0],"combat_reaction_left":[23,.04,-10,PI/2],"combat_reaction_right":[17,.04,-10,-PI/2],"combat_reaction_back":[20,.04,-13,PI],"combat_grab":[20,.04,-7,0],"combat_grab_lowhp":[20,.04,-7,0],"combat_crowd":[20,.04,-5,0]})
	fixtures.merge({"physics_police":[20,.04,-7,0],"physics_suit":[20,.04,-7,0],"physics_polo":[20,.04,-7,0],"physics_female":[20,.04,-7,0],"physics_left":[22.3,.04,-9.3,PI/2],"physics_right":[17.7,.04,-9.3,-PI/2],"physics_wall":[20,.04,-10.7,0]})
	fixtures.merge({"shooting_near":[23,.04,-3,0],"shooting_far":[23,.04,-3,0],"shooting_head_far":[23,.04,-3,0],"shooting_wall":[23,.04,-10.7,0],"shooting_elite":[23,.04,-3,0],"shooting_boss":[23,.04,-3,0]})
	fixtures.merge({"shooting_reactions":[23,.04,-3,0],"shooting_chain":[23,.04,-3,0],"shooting_chain_heavy":[23,.04,-3,0],"shooting_chain_wall":[31,.04,7.8,0]})
	fixtures.merge({"transition_walk":[23,.04,-3,0],"transition_near":[23,.04,-3,0],"transition_edge_near":[23,.04,-1.1,0],"transition_edge_far":[23,.04,-.6,0],"transition_runner_near":[23,.04,-3,0],"transition_runner_far":[23,.04,-2,0],"transition_far":[23,.04,-2,0],"transition_long":[44,.04,-7,PI/2],"transition_front":[23,.04,-3,0],"transition_back":[23,.04,-9,PI],"transition_left":[26,.04,-6,PI/2],"transition_right":[20,.04,-6,-PI/2]})
	fixtures.merge({"population_f2boss":[9.5,3.64,21,0],"population_f2crowd":[38.5,3.64,15.5,PI],"population_f3crowd":[38.5,7.24,15.5,PI],"population_f4lounge":[10,10.84,7.2,0]})
	make_materials()
	for level in spec.levels:
		build_level(level)
	# Refinement of the source garage: a roof makes its ceiling fixture credible.
	box_at(Vector3(4,.15,8),Vector3(48,3.275,16),materials.ceil)
	build_dressing()
	for light in lighting.lights:
		build_light(light,float({"G":0,"F2":3.6,"F3":7.2,"F4":10.8}[light.floor]),light.floor)
	build_environment()
	indoor_lights.setup(self)
	static_prop_stats=preload("res://scripts/static_render.gd").prepare(self)
	static_batch_stats=preload("res://addons/ai_engine/performance/static_boxes.gd").build(self,static_boxes)
	static_boxes.clear()
	build_occlusion()
	preload("res://scripts/bank_indirect.gd").mark(self)
	if "--bank-bake-source" not in OS.get_cmdline_user_args():
		indirect_stats=preload("res://scripts/bank_indirect.gd").attach(self)
		print("BANK_LIGHTING ",JSON.stringify(indirect_stats))
	reflections.build(self)
	build_player()
	flashlight_lighting.setup(self)
	add_child(infected_audio);infected_audio.setup(self)
	feedback.setup(self)
	build_ui()
	viewmodel_lighting.setup(self)
	door_lighting.setup(self)
	var review_views: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/review_views.json"))
	for key in review_views:fixtures["review_"+key] = review_views[key]
	for key in {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"run":KEY_SHIFT}:
		if not InputMap.has_action(key):
			InputMap.add_action(key)
			var event := InputEventKey.new()
			event.physical_keycode = {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"run":KEY_SHIFT}[key]
			InputMap.action_add_event(key,event)
	reset_fixture("default")
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ai-session="):
				testing = true
				Input.use_accumulated_input = false
				var bridge := preload("res://addons/ai_engine/testing/bridge.gd").new()
				bridge.session = arg.trim_prefix("--ai-session=")
				profiler.recording_root=bridge.session.path_join("performance")
				bridge.adapter = preload("res://scripts/exploration_adapter.gd").new(self)
				add_child(bridge)
	if OS.is_debug_build() and "--performance-benchmark" in OS.get_cmdline_user_args():testing=true
	for viewport in find_children("*","SubViewport",true,false):profiler.register_viewport(str(viewport.get_path()),viewport)
	if not testing:
		# The default fixture starts play with the HUD; capture aim immediately.
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func make_materials() -> void:
	for key in {"wall":"92958b","wallgreen":"697b71","wallwood":"615544","concrete":"7e817b","tile":"9b9a86","office":"6e756c","lino":"727b69","wood":"69533c","woodlight":"877153","kitchen":"99a5a0","ceil":"85877e","metal":"474e4d","asphalt":"343b3d","grate":"434b49","stairs":"6e746b"}:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color({"wall":"92958b","wallgreen":"697b71","wallwood":"615544","concrete":"7e817b","tile":"9b9a86","office":"6e756c","lino":"727b69","wood":"69533c","woodlight":"877153","kitchen":"99a5a0","ceil":"85877e","metal":"474e4d","asphalt":"343b3d","grate":"434b49","stairs":"6e746b"}[key])
		m.roughness = 0.87
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		materials[key] = m
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://shaders/bank_glass.gdshader")
	glass.set_shader_parameter("grime_texture",load(dressing.surfaces.glass_dirt.resource))
	materials.glass = glass
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("d1dccb")
	lamp.emission_enabled = true
	lamp.emission = Color("d1dccb")
	lamp.emission_energy_multiplier = 2.0
	materials.lamp = lamp
	var texture_mapping := {"tile":"tile","kitchen":"kitchen","concrete":"concrete","stairs":"floor","office":"carpet","lino":"floor","ceil":"concrete","wood":"wood","woodlight":"wood","wallwood":"wood","asphalt":"concrete","metal":"steel_panels","grate":"steel_panels"}
	for key in texture_mapping:
		var texture_key: String = texture_mapping[key]
		if dressing.get("surfaces",{}).has(texture_key):
			var m: StandardMaterial3D = materials[key]
			m.albedo_color = Color.WHITE
			m.albedo_texture = load(dressing.surfaces[texture_key].resource)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5,0.5,0.5)
			if key=="asphalt":m.albedo_color=Color("565d61")
			if key in ["metal","grate"]:
				m.metallic=.55
				m.roughness=.57
				m.albedo_color=Color("b4bbb4")
	if dressing.get("surfaces",{}).has("plaster"):
		for key in ["wall","wallgreen"]:
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/aged_wall.gdshader")
			m.set_shader_parameter("base_texture",load(dressing.surfaces.plaster.resource))
			materials[key] = m
		var lower := ShaderMaterial.new()
		lower.shader = preload("res://shaders/aged_wall.gdshader")
		lower.set_shader_parameter("base_texture",load(dressing.surfaces.plaster.resource))
		lower.set_shader_parameter("paint_tint",Color("6a8074"))
		materials.lower_wall = lower
	preload("res://scripts/surface_materials.gd").apply(self)

func box_at(size: Vector3, pos: Vector3, material: Material, collision := true, parent: Node3D = self) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = pos
	parent.add_child(mesh)
	if parent==self and material!=materials.get("glass"):static_boxes.append(mesh)
	# Opaque structural boxes only: real door gaps/windows remain open. The
	# proxy is slightly inset so it cannot hide pixels outside the source wall.
	if collision and parent==self and material!=materials.get("glass") and size.x*size.y+size.x*size.z+size.y*size.z>4.0 and minf(size.x,minf(size.y,size.z))>.04:
		var proxy:=BoxMesh.new();proxy.size=size-Vector3.ONE*.02
		for vertex in proxy.get_faces():occlusion_vertices.append(vertex+pos)
	if collision:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		body.add_child(col)
		mesh.add_child(body)
	return mesh

func build_occlusion() -> void:
	var indices:=PackedInt32Array();indices.resize(occlusion_vertices.size())
	for i in indices.size():indices[i]=i
	var occluder:=ArrayOccluder3D.new();occluder.set_arrays(occlusion_vertices,indices)
	var instance:=OccluderInstance3D.new();instance.name="StructuralOcclusion";instance.occluder=occluder;add_child(instance)
	get_viewport().use_occlusion_culling=true
	occlusion_vertices.clear()

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

func build_dressing() -> void:
	for prop in dressing.props:
		var pin: Dictionary = dressing.pins[prop.model]
		var scene: PackedScene = load(pin.resource)
		var node := scene.instantiate() as Node3D
		node.name = prop.id
		node.position = Vector3(prop.position[0],prop.position[1],prop.position[2])
		node.rotation.y = deg_to_rad(prop.yaw)
		node.scale = Vector3(prop.scale[0],prop.scale[1],prop.scale[2])
		add_child(node)
		node.set_meta("asset_entity",prop.id)
		if prop.collision:
			add_mesh_collisions(node)
	for work in dressing.get("millwork",[]):
		var pos := Vector3(work.position[0],work.position[1],work.position[2])
		var size := Vector3(work.size[0],work.size[1],work.size[2])
		if work.get("kind","")=="safe_cabinet":
			box_at(size,pos+Vector3(0,size.y/2,0),materials.metal)
			continue
		var green := StandardMaterial3D.new()
		green.albedo_color = Color("294e49")
		green.albedo_texture=load(dressing.surfaces.wood.resource)
		green.uv1_triplanar=true
		green.uv1_world_triplanar=true
		box_at(Vector3(size.x,.05,size.z),pos+Vector3(0,size.y,0),green)
		for x in [-size.x/2+.2,size.x/2-.2]:
			for z in [-size.z/2+.2,size.z/2-.2]:
				box_at(Vector3(.06,size.y,.06),pos+Vector3(x,size.y/2,z),materials.metal)
		var net := ShaderMaterial.new()
		net.shader=preload("res://shaders/table_net.gdshader")
		box_at(Vector3(.002,.1525,size.z+.04),pos+Vector3(0,size.y+.10375,0),net,false)
		# White binding and perimeter lines belong to the playing surface; the
		# net itself is an open woven grid, not a solid concrete strip.
		var binding := materials.wood.duplicate() as StandardMaterial3D
		binding.albedo_color=Color("cec9b7")
		for z in [-size.z/2-.025,size.z/2+.025]:
			box_at(Vector3(.025,.20,.025),pos+Vector3(0,size.y+.1,z),materials.metal,false)
		box_at(Vector3(.012,.016,size.z+.04),pos+Vector3(0,size.y+.176,0),binding,false)
		for x in [-size.x/2+.012,size.x/2-.012]:
			box_at(Vector3(.02,.001,size.z),pos+Vector3(x,size.y+.026,0),binding,false)
		for z in [-size.z/2+.012,0.0,size.z/2-.012]:
			box_at(Vector3(size.x,.001,.015),pos+Vector3(0,size.y+.026,z),binding,false)

func add_mesh_collisions(node: Node) -> void:
	for child in node.get_children():
		add_mesh_collisions(child)
	if node is MeshInstance3D and node.mesh:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape: ConcavePolygonShape3D = node.mesh.create_trimesh_shape()
		shape.backface_collision = true
		col.shape = shape
		body.add_child(col)
		node.add_child(body)

func build_door(definition: Dictionary, base: float) -> void:
	var node := preload("res://scripts/exploration_door.gd").new()
	add_child(node)
	var designed: Dictionary = definition.duplicate(true)
	designed.merge(door_design[definition.id],true)
	node.setup(designed,base,dressing.pins,materials)
	for mesh in node.find_children("*","GeometryInstance3D",true,false):mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	doors[definition.id] = node
	if definition.id in ["g_inner","g_outer"]:
		var led := StandardMaterial3D.new()
		led.albedo_color = Color("8d2824")
		led.emission_enabled = true
		led.emission = Color("8d2824")
		for offset in [-.14,.14]:
			box_at(Vector3(.05,.12,.12),Vector3(definition.x+offset,base+2.35,definition.z),led,false)
	var normal := Vector3(0,0,1) if definition.axis=="x" else Vector3(-1,0,0)
	var approach_distance := 2.2 if definition.id=="g_gate" else 1.4 if node.leaves.size()>1 or node.mode=="lift" else 1.85
	for side in [-1,1]:
		var point: Vector3 = Vector3(definition.x,base+.04,definition.z)+normal*approach_distance*float(side)
		var direction: Vector3 = -normal*float(side)
		fixtures["door_"+str(definition.id)+("_a" if side==1 else "_b")] = [point.x,point.y,point.z,atan2(-direction.x,-direction.z)]

func build_light(source: Dictionary, base: float, floor_id: String) -> void:
	# Original functional zones define fixture locations; no player-following ambient fill.
	var color := Color.hex(int(source.color)*256+255)
	if source.fixture:color=color.lerp(Color(1.0,.98,.94),.3)
	if source.fixture:
		var fluorescent: bool=str(source.get("zone",""))!="电梯"
		var profile: Dictionary=lighting.fluorescent_profile if fluorescent else {}
		if source.get("zone","")!="电梯":
			var fixture := (load(dressing.pins.fluorescent.resource) as PackedScene).instantiate() as Node3D
			fixture.position = Vector3(source.x,base+3.2-dressing.pins.fluorescent.size[1],source.z)
			add_child(fixture)
			# The imported diffuser used a fixed display-only glow even when the
			# authored lamp was off. Share calibrated emissive materials by source
			# material/energy; LightmapGI now bakes the actual luminous tube area.
			for mesh in fixture.find_children("*","MeshInstance3D",true,false):
				for surface in mesh.mesh.get_surface_count():
					var original: Material=mesh.get_active_material(surface)
					if original is not StandardMaterial3D or not original.emission_enabled:continue
					var key:=str(original.get_rid())+":"+str(source.energy)+":"+str(source.color)
					if not fixture_materials.has(key):
						var calibrated: StandardMaterial3D=original.duplicate()
						calibrated.emission_energy_multiplier=float(source.energy)*6.0
						calibrated.emission=color
						fixture_materials[key]=calibrated
					mesh.set_surface_override_material(surface,fixture_materials[key])
		var light := SpotLight3D.new()
		light.name = source.id
		light.position = Vector3(source.x,base+2.70,source.z)
		light.rotation.x = -PI/2
		light.light_color = color
		# Calibrate the authored room levels for the broader diffuser rolloff.
		# Use exactly this distribution in the indirect bake as well.
		light.light_energy = float(source.energy)*float(profile.get("energy_scale",1.0))
		light.spot_range = min(float(source.range),10.0)
		# Keep broad fixture coverage without stretching a single shadow map
		# across a nearly hemispherical 170-degree projection.
		light.spot_angle = float(profile.get("half_angle",75.0))
		# A smooth edge replaces the old almost-flat cone and its curved wall
		# cutoff. Housing limits grazing emission; reflected light fills above it.
		light.spot_angle_attenuation = float(profile.get("angular_attenuation",.25))
		light.spot_attenuation = float(profile.get("distance_attenuation",1.0))
		light.shadow_enabled = true
		light.light_bake_mode=Light3D.BAKE_DYNAMIC
		# Filtered PCF avoids unstable PCSS blocker searches on close jambs.
		light.light_size=0.0
		# Downward room lights cannot see actors through the solid floor slab.
		# Stationary architecture/props also use conservative floor bounds;
		# moving doors stay shared on layer 1. Open stairs keep all caster layers.
		if "楼梯" not in str(source.get("zone","")):
			var floor_index:=int(round(base/3.6))
			var floor_layer:=1 << (floor_index+1)
			# Architecture is assigned to a per-floor layer by static_render.gd.
			# The old default mask (layer 1) left room walls unlit and made the
			# baked snapshot black; keep layer 1 for actors and doors as well.
			light.light_cull_mask=1 | floor_layer
			light.shadow_caster_mask=1 | floor_layer
			light.set_meta("enclosed_floor",floor_index)
		else:
			light.light_cull_mask=1 | 2 | 4 | 8 | 16
		# The narrower projection needs much less bias than the old 85-degree
		# cone. Large depth offsets leak adjacent-room light through corners.
		light.shadow_bias = .08
		light.shadow_normal_bias = .1
		add_child(light)
	else:
		var housing := (load(dressing.pins.wall_lamp.resource) as PackedScene).instantiate() as Node3D
		housing.position = Vector3(source.x,base+source.y+.025,source.z)
		housing.rotation.y = deg_to_rad(float(source.get("housing_yaw",0)))
		add_child(housing)
		if source.get("mount","")=="pole":
			box_at(Vector3(.12,source.y+.40,.12),Vector3(source.x+.32,base+(source.y+.40)/2,source.z),materials.metal)
		var light := OmniLight3D.new()
		light.name = source.id
		light.position = Vector3(source.x,base+source.y,source.z)
		light.light_color = color
		light.light_energy = float(source.energy)
		light.omni_range = min(float(source.range),8.0)
		light.shadow_enabled = true
		light.light_bake_mode=Light3D.BAKE_DYNAMIC
		light.light_size=.035
		light.light_cull_mask=1 | (1 << (int(round(base/3.6))+1))
		light.shadow_bias = .08
		light.shadow_normal_bias = .02
		add_child(light)

func build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("070c12")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("879795")
	env.ambient_light_energy = lighting.environment.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.20
	env.ssao_enabled = true
	env.ssao_radius = .55
	env.ssao_intensity = .95
	env.glow_enabled = true
	env.glow_intensity = .12
	env.fog_enabled = true
	env.fog_light_color = Color("19222a")
	env.fog_density = lighting.environment.fog_density
	world.environment = env
	add_child(world)

func build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 9
	player.floor_snap_length = 0.3
	player.floor_max_angle = deg_to_rad(48)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.72
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.88
	player.add_child(col)
	add_child(player)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.near = 0.04
	camera.fov = 75
	camera.current = true
	player.add_child(camera)
	# A moving parent must not apply its discrete transform a second time to
	# the render camera. Keep the node parent for ownership, use world space.
	camera.top_level=true
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_motion.setup(self)
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(-.23,-.25,-.53418)
	flashlight.light_color = Color("d2d7c7")
	flashlight.light_energy = 1.15
	flashlight.spot_range = 14
	flashlight.spot_angle = 28
	flashlight.spot_angle_attenuation = 1.5
	flashlight.spot_attenuation = 1.25
	flashlight.shadow_enabled = true
	flashlight.light_bake_mode=Light3D.BAKE_DISABLED
	flashlight.visible = true
	camera.add_child(flashlight)

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var post := ColorRect.new()
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://shaders/atmosphere.gdshader")
	post.material = shader
	layer.add_child(post)
	held_weapon = preload("res://scripts/held_weapon.gd").new()
	layer.add_child(held_weapon)
	held_weapon.setup(dressing.pins.torch_hand.resource,dressing.pins.flashlight.resource)
	add_child(firearms);firearms.setup(self,layer)
	damage_overlay=ColorRect.new()
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_overlay.color=Color(0.5,0.02,0.01,0)
	damage_material=ShaderMaterial.new();damage_material.shader=preload("res://shaders/combat_vignette.gdshader");damage_overlay.material=damage_material
	damage_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(damage_overlay)
	ui=preload("res://ui/shell.gd").new();add_child(ui);ui.setup(self)

func _physics_process(dt: float) -> void:
	if not testing:
		advance(dt)

func _process(_dt: float) -> void:
	if camera==null or ui==null or not camera.is_current() or ui.blocks_world():return
	camera_motion.render(1.0 if frozen_presentation else Engine.get_physics_interpolation_fraction())
	update_indoor_lights()
	viewmodel_lighting.render()

func advance(dt: float) -> void:
	if ui.blocks_world():ui.advance(dt);return
	var started:=Time.get_ticks_usec()
	if not infected_ready:
		navigation.build(self)
		for source in infected_data.enemies:
			var actor=preload("res://scripts/infected.gd").new()
			add_child(actor)
			actor.setup(self,source,infected_data.types[source.type],infected_data.pins[source.model])
			var nearest: int=navigation.nearest(actor.home,true)
			assert(nearest>=0,"No supported infected spawn: "+str(source.id))
			var supported: Vector3=navigation.graph.get_point_position(nearest)
			actor.spawn_adjustment=supported-actor.home
			actor.home=supported;actor.position=supported+Vector3.UP*.04
			infected.append(actor)
		infected_ready=true
		reset_infected(current_fixture)
	profiler.begin_tick()
	camera_motion.begin_tick()
	update_camera() # restore authoritative pose before melee/feedback queries
	var stage:=profiler.mark()
	tick_count += 1
	navigation.begin_frame()
	var axes := Vector2(float(held_actions.get("right",false))-float(held_actions.get("left",false)),float(held_actions.get("back",false))-float(held_actions.get("forward",false))).limit_length(1.0) if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED or testing else Vector2.ZERO
	if player_dead or feedback.is_grabbed():axes=Vector2.ZERO
	feedback.advance(dt,axes.length()>.1)
	hurt_cooldown=maxf(0,hurt_cooldown-dt);strike_cooldown=maxf(0,strike_cooldown-dt)
	if strike_time>=0:
		strike_time+=dt
		if strike_time>=.17 and not strike_applied:
			strike_applied=true;apply_player_strike()
		if strike_time>.42:strike_time=-1
	var direction := Vector3(axes.x,0,axes.y).rotated(Vector3.UP,player.rotation.y)
	var speed := 4.6 if held_actions.get("run",false) else 2.8
	player.velocity.x = direction.x*speed
	player.velocity.z = direction.z*speed
	player.velocity.y = -1.0 if player.is_on_floor() else player.velocity.y-20*dt
	player.move_and_slide()
	update_camera() # world-space camera must follow before gameplay ray queries
	var wall_distance:=sample_weapon_wall_distance()
	var wall_rate:=12.0 if wall_distance<weapon_wall_filtered else 5.0
	weapon_wall_filtered=move_toward(weapon_wall_filtered,wall_distance,wall_rate*dt)
	if firearms.selected=="torch":
		held_weapon.strike_time=strike_time
		held_weapon.advance(tick_count,axes.length()>.1,wall_distance)
		flashlight.transform = held_weapon.light_transform()
	firearms.advance(dt,axes.length()>.1,weapon_wall_filtered)
	profiler.end_scope("player_weapon",stage);stage=profiler.mark()
	for d in doors.values():
		d.advance(dt)
	navigation.update_doors()
	profiler.end_scope("doors_navigation",stage);stage=profiler.mark()
	crowd.rebuild(infected)
	for enemy in infected:
		enemy.advance(dt)
		if enemy.active and enemy.mode!="dead":crowd.update(enemy)
	profiler.end_scope("infected",stage);stage=profiler.mark()
	infected_audio.advance(dt)
	stage=profiler.mark()
	update_camera()
	update_combat_ui()
	ui.advance(dt)
	flashlight_lighting.advance(dt)
	door_lighting.advance()
	viewmodel_lighting.advance(dt)
	camera_motion.commit_tick()
	profiler.end_scope("camera_ui",stage)
	profiler.count("routes",navigation.queries_this_frame)
	profiler.end_tick()
	tick_cost_usec=Time.get_ticks_usec()-started
	if tick_count>3:peak_tick_cost_usec=maxi(peak_tick_cost_usec,tick_cost_usec)

func sample_weapon_wall_distance() -> float:
	var basis: Basis=camera.global_basis
	var nearest: float=10.0
	nearest=minf(nearest,weapon_wall_probe(basis,Vector2.ZERO))
	nearest=minf(nearest,weapon_wall_probe(basis,Vector2(-.12,0)))
	nearest=minf(nearest,weapon_wall_probe(basis,Vector2(.12,0)))
	nearest=minf(nearest,weapon_wall_probe(basis,Vector2(0,-.08)))
	nearest=minf(nearest,weapon_wall_probe(basis,Vector2(0,.08)))
	return nearest

func weapon_wall_probe(basis: Basis, offset: Vector2) -> float:
	var origin: Vector3=camera.global_position+basis.x*offset.x+basis.y*offset.y
	var query:=PhysicsRayQueryParameters3D.create(origin,origin-basis.z*1.15,1)
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	return origin.distance_to(hit.position) if not hit.is_empty() else 10.0

func update_camera() -> void:
	camera_motion.physics_pose()
	update_indoor_lights()

func update_indoor_lights() -> void:
	indoor_lights.update(get_viewport().get_camera_3d())
	reflections.update(get_viewport().get_camera_3d())

func update_combat_ui() -> void:
	damage_material.set_shader_parameter("strength",feedback.damage_time/.45*feedback.damage_strength)
	damage_material.set_shader_parameter("direction",feedback.damage_direction)
	damage_material.set_shader_parameter("grabbed",feedback.grab_blend)
	damage_material.set_shader_parameter("dead",feedback.death_blend)

func aimed_door() -> String:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*2.6,5)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		for id in doors:
			if doors[id].owns(hit.collider):
				return id
	return ""

func _input(event: InputEvent) -> void:
	if testing and not event.get_meta("ai_bridge_input",false):
		get_viewport().set_input_as_handled();return
	if ui!=null and ui.handle_event(event):return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F8 or event.physical_keycode==KEY_F8:
			profiler.toggle_hud();profiler.hud.position=Vector2(18,120*ui.font_factor);return
		if event.keycode==KEY_F9 or event.physical_keycode==KEY_F9:profiler.manual_record();return
	# Rendered automation uses the same normal input handler, but an unrelated
	# desktop mouse move must not rotate its fixed fixture/camera between commands.
	# Some Windows accessibility/remote keyboards supply a valid logical key
	# with an unrelated scan code. Keep physical WASD layouts when recognized,
	# then fall back to logical keys instead of silently dropping the action.
	var code: int=0
	if event is InputEventKey:
		var supported: Array=[KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_E,KEY_F,KEY_R,KEY_1,KEY_2,KEY_3,KEY_4,KEY_ESCAPE]
		code=event.physical_keycode if event.physical_keycode in supported else event.keycode
	if event is InputEventKey:
		for action in {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"run":KEY_SHIFT}:
			if code=={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"run":KEY_SHIFT}[action]:held_actions[action]=event.pressed
	if event is InputEventMouseMotion and (testing or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED):
		player.rotation.y -= event.relative.x*0.0025*float(ui.settings.sensitivity)
		pitch = clampf(pitch-event.relative.y*0.0025*float(ui.settings.sensitivity),-1.25,1.25)
		firearms.view.mouse_motion(event.relative)
		update_camera()
	if event is InputEventMouseButton and event.pressed and not testing:
		if Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and not player_dead and (testing or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED):
		if event.button_index==MOUSE_BUTTON_LEFT and firearms.selected!="torch":firearms.press_trigger(event.pressed)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and firearms.shove():
			strike_kind="hit" if event.button_index==MOUSE_BUTTON_LEFT else "push"
			strike_time=0;strike_applied=false;strike_cooldown=.52
	if event is InputEventKey and event.pressed and not event.echo:
		if (testing or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED) and not player_dead:feedback.struggle(code)
		if code==KEY_R:
			if player_dead:reset_fixture("default")
			elif testing or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:firearms.reload()
		if code in [KEY_1,KEY_2,KEY_3,KEY_4] and (testing or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED):
			firearms.select_weapon({KEY_1:"pistol",KEY_2:"shotgun",KEY_3:"torch",KEY_4:"baton"}[code])
		if code==KEY_F:
			flashlight.visible = not flashlight.visible
		if code==KEY_E and not player_dead:
			update_camera()
			var id := aimed_door()
			if not id.is_empty():
				doors[id].toggle(player.global_position)

func reset_fixture(fixture: String) -> bool:
	if not fixtures.has(fixture):
		return false
	if ui!=null:ui.reset_play()
	var point: Array = fixtures[fixture]
	current_fixture=fixture;player_hp=100;player_dead=false;kills=0;hurt_cooldown=0;strike_cooldown=0;strike_time=-1;last_combat_event=""
	weapon_wall_filtered=10.0
	feedback.reset();tick_cost_usec=0;peak_tick_cost_usec=0
	player.position = Vector3(point[0],point[1],point[2])
	player.velocity = Vector3.ZERO
	held_actions.clear()
	player.rotation.y = point[3]
	pitch = float(point[4]) if point.size()>4 else 0.0
	camera.rotation.x = pitch
	flashlight.visible = true
	tick_count = 0
	held_weapon.inspect_grip("player")
	# Earlier hand/architecture fixtures deliberately keep the torch. Normal
	# play and firearm fixtures start with the new pistol.
	firearms.reset("pistol" if fixture=="default" or fixture.begins_with("firearms_") or fixture.begins_with("combat_") or fixture.begins_with("physics_") else "torch")
	if fixture.begins_with("baton_"):firearms.reset("pistol")
	if fixture.begins_with("blood_"):firearms.reset("pistol")
	if fixture.begins_with("archetype_"):firearms.reset("pistol")
	if fixture.begins_with("shooting_") or fixture.begins_with("transition_"):firearms.reset("pistol")
	for d in doors.values():
		d.reset_closed()
	if infected_ready:reset_infected(fixture)
	infected_audio.reset()
	camera_motion.reset()
	update_camera();update_combat_ui()
	viewmodel_lighting.advance(0.0,true)
	flashlight_lighting.advance(0.0)
	door_lighting.advance(true)
	if fixture=="ui_title":ui.has_run=false;ui.title_screen()
	return true

func reset_infected(fixture: String) -> void:
	var architecture_fixture: bool=fixture.begins_with("review_") or fixture.begins_with("door_") or "stairs" in fixture and not fixture.begins_with("infected_")
	var physics_target: Node=null
	var archetype_target: Node=null
	var shooting_target: Node=null
	if fixture.begins_with("shooting_") or fixture.begins_with("transition_"):
		for enemy in infected:
			if (enemy.definition.type==fixture.trim_prefix("shooting_") if fixture in ["shooting_elite","shooting_boss"] else enemy.definition.type=="runner" if fixture.begins_with("transition_runner") else enemy.definition.model=="police_male01"):
				shooting_target=enemy;break
	var chain_targets: Array=[]
	if fixture.begins_with("shooting_chain"):
		chain_targets.append(shooting_target)
		if fixture=="shooting_chain_heavy":
			for enemy in infected:
				if enemy.definition.type=="boss":chain_targets.append(enemy);break
		for enemy in infected:
			if chain_targets.size()>=4:break
			if enemy.definition.type=="z" and not enemy in chain_targets:chain_targets.append(enemy)
	if fixture.begins_with("archetype_"):
		var type_key:=fixture.split("_")[1]
		for enemy in infected:
			if enemy.definition.type==type_key:archetype_target=enemy;break
	if fixture.begins_with("physics_"):
		var model_key: String={"physics_suit":"male_suit","physics_polo":"male_polo_jeans","physics_female":"female_formal"}.get(fixture,"police_male01")
		for enemy in infected:
			if enemy.definition.model==model_key:physics_target=enemy;break
	for i in range(infected.size()):
		var enemy=infected[i]
		enemy.ragdoll.reset()
		enemy.pending_dt=0;enemy.resting_position=Vector3.INF
		enemy.fixture_facing_locked=fixture.begins_with("combat_reaction_") or fixture.begins_with("physics_") or fixture.begins_with("shooting_")
		enemy.anchored=enemy.definition.options.get("stairCrowd",false) or enemy.definition.options.get("outside",false)
		enemy.active=not architecture_fixture
		if fixture.begins_with("infected_"):enemy.active=i<4 if fixture=="infected_showcase" else i==0
		if fixture.begins_with("firearms_"):enemy.active=i==0 and fixture!="firearms_range"
		if fixture.begins_with("combat_"):enemy.active=i<16 if fixture=="combat_crowd" else i==0
		if fixture.begins_with("physics_"):enemy.active=enemy==physics_target
		if fixture.begins_with("shooting_") or fixture.begins_with("transition_"):enemy.active=enemy==shooting_target
		if not chain_targets.is_empty():enemy.active=enemy in chain_targets and (fixture!="shooting_chain_wall" or chain_targets.find(enemy)<2)
		if fixture.begins_with("baton_"):enemy.active=i<3 if fixture=="baton_crowd" else i==0 and fixture!="baton_range"
		if fixture.begins_with("blood_"):enemy.active=i==0
		if fixture.begins_with("audio_"):enemy.active=i==0
		if fixture.begins_with("archetype_"):enemy.active=enemy==archetype_target
		enemy.visible=enemy.active;enemy.collision_layer=8 if enemy.active else 0;enemy.collision_mask=11 if enemy.active else 0
		enemy.position=enemy.home+Vector3.UP*.04;enemy.rotation.y=enemy.definition.yaw
		enemy.hp=float(enemy.stats.hp)*float(enemy.definition.options.get("hpMul",1));enemy.mode="idle";enemy.state_time=0;enemy.clock=0;enemy.stagger=0;enemy.cooldown=0;enemy.path_timer=0;enemy.path=PackedVector3Array();enemy.velocity=Vector3.ZERO;enemy.hit_count=0;enemy.detection=false;enemy.lost_time=0
		if fixture.begins_with("infected_") and enemy.active:
			enemy.position=Vector3(20,.04,-10 if fixture=="infected_chase" else -8.25)
			enemy.anchored=false;enemy.rotation.y=PI
			if fixture=="infected_wall":enemy.position=Vector3(31,.04,3.2)
			if fixture=="infected_stairs":enemy.position=Vector3(35.5,.04,16.5)
			if fixture=="infected_showcase":enemy.position=Vector3(22+i*2,.04,-9);enemy.anchored=true
		if fixture.begins_with("firearms_") and enemy.active:
			enemy.position=Vector3(20,.04,-10);enemy.rotation.y=PI;enemy.anchored=true
			if fixture=="firearms_wall":enemy.position=Vector3(31,.04,3.2)
			if fixture=="firearms_close":enemy.position=Vector3(20,.04,-8.25);enemy.anchored=false
		if fixture.begins_with("combat_") and enemy.active:
			enemy.position=Vector3(20,.04,-10);enemy.rotation.y=PI;enemy.anchored=true
			if fixture.begins_with("combat_reaction_"):enemy.hp=250 # isolated nonfatal pose observation target
			if fixture in ["combat_grab","combat_grab_lowhp"]:enemy.position.z=-8.05;enemy.anchored=false
			if fixture=="combat_grab_lowhp":enemy.hp=24
			if fixture=="combat_crowd":
				var desired:=Vector3(18+(i%4)*1.25,.04,-9-floori(float(i)/4)*1.20)
				var support: int=navigation.nearest(desired)
				assert(support>=0,"Crowd fixture must have physical support")
				enemy.position=navigation.graph.get_point_position(support)+Vector3.UP*.04;enemy.anchored=false
		if fixture.begins_with("physics_") and enemy.active:
			enemy.position=Vector3(20,.04,-13.1 if fixture=="physics_wall" else -9.3);enemy.rotation.y=PI;enemy.anchored=true;enemy.hp=65
		if fixture.begins_with("shooting_") and enemy.active:
			enemy.position=Vector3(23,.04,-13.1 if fixture=="shooting_wall" else -11 if fixture=="shooting_far" else -7.2 if fixture=="shooting_head_far" else -5.3)
			enemy.rotation.y=PI;enemy.anchored=true;enemy.cooldown=120
			if fixture=="shooting_reactions":enemy.hp=500 # Explicit nonfatal pose observation only.
			if not chain_targets.is_empty():
				var slot: int=chain_targets.find(enemy)
				enemy.position=[Vector3(23,.04,-5.3),Vector3(23,.04,-7.5),Vector3(25.2,.04,-7.5),Vector3(23,.04,-10.7)][slot]
				if fixture=="shooting_chain_wall":enemy.position=Vector3(31,.04,5.5 if slot==0 else 3.2)
		if fixture.begins_with("transition_") and enemy.active:
			enemy.position=Vector3(23,.04,-6);enemy.rotation.y=PI;enemy.anchored=true;enemy.fixture_facing_locked=true;enemy.cooldown=120
			if fixture in ["transition_front","transition_back","transition_left","transition_right"]:enemy.hp=500
			if fixture in ["transition_far","transition_runner_far"]:enemy.position.z=-12
			if fixture=="transition_walk":enemy.position.z=-10;enemy.anchored=false;enemy.fixture_facing_locked=false
			if fixture=="transition_long":enemy.position=Vector3(8,.04,-7);enemy.rotation.y=-PI/2
		if fixture.begins_with("baton_") and enemy.active:
			enemy.position=Vector3(20,.04,-8.35);enemy.rotation.y=PI;enemy.anchored=true;enemy.fixture_facing_locked=true;enemy.hp=250;enemy.cooldown=60
			if fixture=="baton_far":enemy.position.z=-9.4
			if fixture=="baton_wall":enemy.position=Vector3(31,.04,4.15)
			if fixture=="baton_crowd":enemy.position.x=19.4+i*.6
			if fixture=="baton_kill":enemy.hp=30
		if fixture.begins_with("blood_") and enemy.active:
			enemy.position=Vector3(20,.04,-13.1 if fixture=="blood_wall" else -9.3);enemy.rotation.y=PI;enemy.anchored=true;enemy.fixture_facing_locked=true;enemy.hp=10000;enemy.cooldown=120
		if fixture.begins_with("audio_") and enemy.active:
			enemy.position=Vector3(31,.04,3.2) if fixture=="audio_wall" else Vector3(20,.04,-10)
			enemy.rotation.y=PI;enemy.anchored=true;enemy.fixture_facing_locked=true;enemy.cooldown=120
		if fixture.begins_with("archetype_") and enemy.active:
			enemy.position=Vector3(20,.04,-11);enemy.rotation.y=PI;enemy.anchored=true;enemy.fixture_facing_locked=true;enemy.cooldown=120
			if fixture.ends_with("_attack"):
				enemy.position.z=-7-(1.60 if enemy.definition.type=="boss" else 1.18 if enemy.definition.type in ["elite","fastElite"] else 1.05)
				enemy.cooldown=0
			if fixture.ends_with("_chase"):enemy.position.z=-13;enemy.anchored=false;enemy.cooldown=0;enemy.fixture_facing_locked=false
		enemy.attack_serial=0;enemy.reactions.reset();enemy.base_pose.clear();enemy.locomotion_recovery=0;enemy.body_collision_count=0;enemy.last_body_collision.clear()
		enemy.reaction_time=10;enemy.reaction_serial=0;enemy.reaction_strength=0;enemy.strong_reaction=false;enemy.last_sample_time=-1;enemy.pose_blend.reset();enemy.native_motion.reset();enemy.pending_pose_dt=0;enemy.skeleton.reset_bone_poses()
		enemy.play_pose(0)

func apply_player_strike() -> void:
	if player_dead:return
	if feedback.is_grabbed() and strike_kind=="push":
		var owner=feedback.grabber
		var away: Vector3=owner.global_position-player.global_position;away.y=0
		owner.receive_hit(0,away.normalized(),{"weapon":"shove"})
		last_combat_event="push:"+str(owner.definition.id)
		return
	var nearest: CharacterBody3D=null;var distance:=1.9
	for enemy in infected:
		if not enemy.active or enemy.mode=="dead":continue
		var target: Vector3=enemy.global_position+Vector3.UP*1.15
		var direction:=target-camera.global_position
		if direction.length()>distance or (-camera.global_basis.z).dot(direction.normalized())<.65:continue
		var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,target,9,[player.get_rid()])
		var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.collider!=enemy:continue
		nearest=enemy;distance=direction.length()
	if nearest:
		var push: Vector3=-camera.global_basis.z;push.y=0
		nearest.receive_hit(32 if strike_kind=="hit" else 0,push.normalized(),{"weapon":"melee" if strike_kind=="hit" else "shove"})
		last_combat_event=strike_kind+":"+str(nearest.definition.id)
	else:
		# Dead actors have no standing movement capsule. Use their current posed
		# hit areas and stop at the first world obstruction, including the floor.
		var direction: Vector3=-camera.global_basis.z
		var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position+direction*1.9,33,[player.get_rid()])
		ray.collide_with_areas=true
		var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider.has_meta("shot_owner"):
			var corpse=hit.collider.get_meta("shot_owner")
			if corpse.active and corpse.mode=="dead":
				var part: String=hit.collider.get_meta("hit_part","Body")
				corpse.receive_hit(0,direction,{"weapon":"shove","part":part,"point":hit.position,"direction":direction})
				firearms.confirm_corpse(hit.position,"shove",part)
				last_combat_event=strike_kind+":corpse:"+str(corpse.definition.id)
				return
		last_combat_event=strike_kind+":miss"

func hurt_player(damage: float,enemy: String,source: Vector3=Vector3.INF) -> void:
	if player_dead or hurt_cooldown>0:return
	for actor in infected:
		if str(actor.definition.id)==enemy:
			infected_audio.request(actor,"bite" if feedback.grabber==actor else "impact");break
	player_hp=maxf(0,player_hp-damage);hurt_cooldown=.65;last_combat_event="hurt:"+enemy
	if source==Vector3.INF:source=player.global_position-camera.global_basis.z
	feedback.hit(damage,source)
	if player_hp<=0:player_dead=true;held_actions.clear();strike_time=-1;firearms.clear_input()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and not testing:
		held_actions.clear()
		firearms.clear_input()
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		if ui!=null and ui.mode=="play":ui.set_mode("pause")

func observe() -> Dictionary:
	var contacts := []
	for i in range(min(player.get_slide_collision_count(),4)):
		var hit := player.get_slide_collision(i)
		var collider := hit.get_collider() as Node3D
		var point := hit.get_position()
		var normal := hit.get_normal()
		contacts.append({"node":str(collider.get_path()),"parent_position":[collider.get_parent().global_position.x,collider.get_parent().global_position.y,collider.get_parent().global_position.z] if collider.get_parent() is Node3D else [],"point":[point.x,point.y,point.z],"normal":[normal.x,normal.y,normal.z]})
	var door_states := {}
	for id in doors:
		door_states[id] = doors[id].state()
	var enemies: Array=[]
	for enemy in infected:enemies.append(enemy.observe())
	var count: int=infected.filter(func(e):return e.active).size()
	return {"infected_audio":infected_audio.observe(),"tick":tick_count,"feedback":feedback.observe(),"performance":{"tick_usec":tick_cost_usec,"peak_tick_usec":peak_tick_cost_usec,"route_queries":navigation.queries_total,"peak_frame_queries":navigation.peak_frame_queries},"firearms":firearms.observe(),"player":{"position":[player.position.x,player.position.y,player.position.z],"yaw":player.rotation.y,"pitch":pitch,"on_floor":player.is_on_floor(),"hp":player_hp,"dead":player_dead},"contacts":contacts,"doors":door_states,"floor_count":4,"enemy_count":count,"actor_count":count+1,"infected":enemies,"navigation":{"ready":navigation.ready,"points":navigation.graph.get_point_count(),"revision":navigation.revision},"kills":kills,"last_combat_event":last_combat_event,"first_person":camera.is_current() and camera.get_parent()==player,"flashlight":flashlight.visible,"held_light":{"side":"left" if firearms.selected=="torch" else "right","mount":"hand" if firearms.selected=="torch" else "weapon","bare_hand":true,"lens_position":[flashlight.position.x,flashlight.position.y,flashlight.position.z]},"held_actions":held_actions.duplicate(),"dressing_count":dressing.props.size()}

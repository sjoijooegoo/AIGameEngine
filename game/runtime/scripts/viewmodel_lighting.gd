extends RefCounted
## Sample the world's baked diffuse probe field for first-person viewports.
## Local direct light copies follow real fixtures; world rays prevent light
## crossing closed walls/doors. Simulation-time filtering remains deterministic.
var world: Node3D
var sources: Array[Light3D]=[]
var targets: Array=[]
var slots: Array=[]
var environments: Array[Environment]=[]
var probe_points:=PackedVector3Array()
var probe_sh:=PackedColorArray()
var probe_cells: Dictionary={}
var ambient_base:=Color.BLACK
var ambient_target:=Color.BLACK
var ambient_current:=Color.BLACK
var probe_samples:=0
var last_sample := -100
var sampled_rays := 0

func setup(owner_world: Node3D) -> void:
	world=owner_world
	var environment: Environment
	for child in world.get_children():
		if child is Light3D:sources.append(child)
		if child is WorldEnvironment:environment=child.environment
	var baked: LightmapGI=world.get_node_or_null("BankStaticGeometry/BankIndirectLight")
	if baked!=null:
		probe_points=RenderingServer.lightmap_get_probe_capture_points(baked.light_data.get_rid())
		probe_sh=RenderingServer.lightmap_get_probe_capture_sh(baked.light_data.get_rid())
		for i in probe_points.size():
			var cell:=Vector3i((probe_points[i]/6.0).floor())
			if not probe_cells.has(cell):probe_cells[cell]=[]
			probe_cells[cell].append(i)
	ambient_base=environment.ambient_light_color.srgb_to_linear()*environment.ambient_light_energy
	ambient_target=ambient_base;ambient_current=ambient_base
	for view in [world.held_weapon,world.firearms.view]:
		var viewport: SubViewport=view.viewport_3d
		viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_PARENT_VISIBLE
		for mesh in viewport.find_children("*","GeometryInstance3D",true,false):mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
		for child in viewport.get_children():
			if child is DirectionalLight3D:child.visible=false
			if child is WorldEnvironment:
				child.environment.ambient_light_color=environment.ambient_light_color
				child.environment.ambient_light_energy=environment.ambient_light_energy
				child.environment.tonemap_mode=environment.tonemap_mode
				child.environment.tonemap_exposure=environment.tonemap_exposure
				environments.append(child.environment)
		var copies: Array=[]
		for i in 3:
			var spot:=SpotLight3D.new();var omni:=OmniLight3D.new();var area:=AreaLight3D.new()
			spot.name="RoomSpot"+str(i);omni.name="RoomOmni"+str(i);area.name="RoomArea"+str(i)
			for light in [spot,omni,area]:
				light.light_bake_mode=Light3D.BAKE_DISABLED
				light.visible=false;viewport.add_child(light)
			copies.append({"spot":spot,"omni":omni,"area":area})
		targets.append(copies)
	for i in 3:slots.append({"source":null,"target":0.0,"weight":0.0})

func sample_indirect(point: Vector3, record := true) -> Color:
	# Godot 4.7.2 produces invalid shader pipelines when a copied LightmapGI
	# capture field lights the weapon viewport. Read the actual bake instead.
	# The L0 SH coefficient is the isotropic diffuse component; direct fixture
	# copies below retain directional shading. This does not reproduce L1/L2.
	var count:=0
	if record:probe_samples=0
	if probe_sh.size()!=probe_points.size()*9 or probe_points.is_empty():return Color.BLACK
	var nearest: Array=[]
	# A 6 m radius only intersects this cell and its 26 neighbours. This
	# preserves the exact nearest-eight selection without a whole-bank scan
	# for every nearby door face.
	var local_indices: Array=[]
	var center:=Vector3i((point/6.0).floor())
	for x in range(-1,2):
		for y in range(-1,2):
			for z in range(-1,2):local_indices.append_array(probe_cells.get(center+Vector3i(x,y,z),[]))
	for i in local_indices:
		var distance:=point.distance_squared_to(probe_points[i])
		if distance>36.0:continue
		if nearest.size()==8 and distance>=float(nearest[-1].distance):continue
		nearest.append({"index":i,"distance":distance})
		nearest.sort_custom(func(a,b):return a.distance<b.distance)
		if nearest.size()>8:nearest.pop_back()
	var result:=Color(0,0,0,0);var total:=0.0
	for candidate in nearest:
		var ray:=PhysicsRayQueryParameters3D.create(point,probe_points[candidate.index],1)
		if record:sampled_rays+=1
		if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		var weight:=1.0/maxf(float(candidate.distance),.04)
		result+=probe_sh[int(candidate.index)*9]*weight*.282095
		total+=weight;count+=1
		if count==4:break
	if record:probe_samples=count
	return result/total if total>0 else Color.BLACK

func score(light: Light3D, point: Vector3) -> float:
	if not light.visible or light.light_energy<=0:return 0.0
	var delta:=point-light.global_position
	var radius: float=light.spot_range if light is SpotLight3D else light.area_range if light is AreaLight3D else light.omni_range
	var distance:=delta.length()
	if distance>=radius:return 0.0
	var weight:=pow(1.0-distance/radius,2.0)*light.light_energy
	if light is SpotLight3D:
		var edge:=cos(deg_to_rad(light.spot_angle))
		var cosine:=(-light.global_basis.z).dot(delta.normalized())
		if cosine<=edge:return 0.0
		weight*=pow(clampf((cosine-edge)/(1.0-edge),0,1),light.spot_angle_attenuation)
	elif light is AreaLight3D:
		weight*=maxf(0.0,(-light.global_basis.z).dot(delta.normalized()))
	return weight

func advance(dt: float, snap := false) -> void:
	if targets.is_empty():return
	if snap or world.tick_count-last_sample>=6 or world.tick_count<last_sample:
		last_sample=world.tick_count;sampled_rays=0
		var point: Vector3=world.camera.global_position
		ambient_target=ambient_base+sample_indirect(point)
		var candidates: Array=[]
		for source in sources:
			var strength:=score(source,point)
			if strength>.002:candidates.append({"source":source,"score":strength})
		candidates.sort_custom(func(a,b):return a.score>b.score)
		var picked: Array=[]
		for candidate in candidates.slice(0,8):
			var light: Light3D=candidate.source
			var ray:=PhysicsRayQueryParameters3D.create(point,light.global_position,1)
			sampled_rays+=1
			if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():picked.append(light)
			if picked.size()==3:break
		# Keep fixtures in the same slots across score changes.
		for slot in slots:
			if slot.source in picked:slot.target=1.0;picked.erase(slot.source)
			else:slot.target=0.0
		for light in picked:
			for slot in slots:
				if slot.target==0:
					slot.source=light;slot.weight=0.0;slot.target=1.0;break
	for slot in slots:slot.weight=float(slot.target) if snap else lerpf(float(slot.weight),float(slot.target),1.0-exp(-dt*9.0))
	ambient_current=ambient_target if snap else ambient_current.lerp(ambient_target,1.0-exp(-dt*9.0))
	render()

func render() -> void:
	if world==null or world.camera==null:return
	var inverse: Transform3D=world.camera.global_transform.affine_inverse()
	for environment in environments:
		var energy:=maxf(maxf(ambient_current.r,ambient_current.g),maxf(ambient_current.b,.00001))
		environment.ambient_light_color=(ambient_current/energy).linear_to_srgb()
		environment.ambient_light_energy=energy
	for copies in targets:
		for i in slots.size():
			var slot: Dictionary=slots[i]
			var source: Light3D=slot.source
			var active: bool=source!=null and source.visible and slot.weight>=.001
			copies[i].spot.visible=active and source is SpotLight3D
			copies[i].omni.visible=active and source is OmniLight3D
			copies[i].area.visible=active and source is AreaLight3D
			if not active:continue
			var light: Light3D=copies[i].spot if source is SpotLight3D else copies[i].area if source is AreaLight3D else copies[i].omni
			light.transform=inverse*source.global_transform
			light.light_color=source.light_color;light.light_energy=source.light_energy*float(slot.weight)
			if source is SpotLight3D:
				light.spot_range=source.spot_range;light.spot_angle=source.spot_angle
				light.spot_attenuation=source.spot_attenuation;light.spot_angle_attenuation=source.spot_angle_attenuation
			elif source is AreaLight3D:
				light.area_range=source.area_range;light.area_attenuation=source.area_attenuation
				light.area_size=source.area_size;light.area_normalize_energy=source.area_normalize_energy
				light.light_specular=source.light_specular
			else:light.omni_range=source.omni_range;light.omni_attenuation=source.omni_attenuation

func observe() -> Dictionary:
	var active: Array=[]
	for slot in slots:
		if slot.source!=null and slot.weight>.001:active.append({"name":str(slot.source.name),"weight":slot.weight})
	return {"baked_probe_count":probe_points.size(),"probe_samples":probe_samples,"sampling_targets":environments.size(),"indirect_mode":"baked_sh_l0","ambient_linear":[ambient_current.r,ambient_current.g,ambient_current.b],"direct_sources":active,"sampled_rays":sampled_rays,"sample_tick":last_sample}

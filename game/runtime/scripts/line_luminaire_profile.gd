extends RefCounted
## One shadowed downward emitter per hanging diffuser. Preserve total energy
## and smooth wall falloff while avoiding three cube-shadow renders per tube.
## Direct emitters only: the v46 indirect bake is intentionally retained.
var world: Node3D
var lights: Array=[]
var fixtures: Array=[]
# These four compact sources are inside the elevator cabins. G_source_10 is
# in the lobby: the legacy bake's zone label must not classify its fixture.
const CABIN_LIGHTS := ["G_source_2","F2_source_2","F3_source_2","F4_source_2"]
const LOBBY_LIGHT := "G_source_10"
var lobby_housing: Node3D

func diffuser() -> Texture2D:
	var img:=Image.create(256,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		var value:=maxf(0.0,cos(PI*(float(y)+.5)/128.0))
		for x in 256:img.set_pixel(x,y,Color(value,value,value,1))
	return ImageTexture.create_from_image(img)

func setup(owner_world: Node3D) -> void:
	world=owner_world
	# Main-menu entry and explicit inspection tools share one set of emitters.
	var existing=world.get_meta("bank_hanging_lights") if world.has_meta("bank_hanging_lights") else null
	if existing!=null:
		lights=existing.lights;fixtures=existing.fixtures;lobby_housing=existing.lobby_housing
		return
	assert(world.indirect_stats.get("loaded",false),"The reference v46 indirect bake must be present")
	world.set_meta("bank_hanging_lights",self)
	# Medium PCSS keeps blocker-dependent penumbrae with a bounded sample budget.
	# This affects positional lights (including the flashlight), not atlas size.
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	var projector:=diffuser()
	for source in world.lighting.lights:
		if not source.fixture or str(source.id) in CABIN_LIGHTS:continue
		var spot: SpotLight3D=world.get_node(str(source.id))
		var energy:=spot.light_energy
		var lobby: bool=str(source.id)==LOBBY_LIGHT
		# The lobby used to miss the fluorescent energy calibration as well.
		if lobby:energy*=float(world.lighting.fluorescent_profile.energy_scale)
		fixtures.append({"id":source.id,"floor":source.floor,"zone":"前楼梯走廊" if lobby else source.zone,"spot_energy":spot.light_energy,"line_total_energy":energy*.7,"range":spot.spot_range})
		var light:=OmniLight3D.new();light.name=str(source.id)+"_Diffuse"
		light.omni_range=spot.spot_range;light.omni_attenuation=1.0
		light.omni_shadow_mode=OmniLight3D.SHADOW_CUBE
		light.light_color=spot.light_color;light.light_energy=energy*.7
		light.shadow_enabled=true;light.shadow_bias=.025;light.shadow_normal_bias=.02;light.light_size=.08
		light.light_cull_mask=spot.light_cull_mask;light.shadow_caster_mask=spot.shadow_caster_mask
		light.light_bake_mode=Light3D.BAKE_DYNAMIC;light.light_projector=projector
		world.add_child(light);light.global_position=spot.global_position
		if lobby:
			add_lobby_housing(source,light)
			# Close walls amplify PCSS blocker-search banding. Filtered PCF keeps
			# actual wall/door/actor occlusion without those broad false stripes.
			light.light_size=0.0
		if spot.has_meta("enclosed_floor"):
			light.set_meta("enclosed_floor",spot.get_meta("enclosed_floor"))
			world.indoor_lights.rooms.append({"light":light,"floor":int(spot.get_meta("enclosed_floor"))})
		world.viewmodel_lighting.sources.append(light);lights.append(light)
		# Keep the original node for inspection but it can never double-light a floor.
		spot.light_energy=0.0;spot.visible=false
		world.indoor_lights.rooms=world.indoor_lights.rooms.filter(func(entry):return entry.light!=spot)
	world.indoor_lights.floor_mask=-1
	world.indoor_lights.update(world.camera)
	# Cube shadow maps use the authored mesh topology. The former subdivision
	# was an area-light projection experiment, and multiplied shadow geometry
	# across the whole bank without improving this point-light configuration.
	# Leave meshes and their existing LightmapGI bindings intact.

func add_lobby_housing(source: Dictionary, light: OmniLight3D) -> void:
	var pin: Dictionary=world.dressing.pins.fluorescent
	lobby_housing=(load(pin.resource) as PackedScene).instantiate()
	lobby_housing.name="LobbyFluorescentHousing"
	# The authored model's Y=0 bottom includes its 0.438 m suspension. The
	# local corridor ceiling is 3.2 m, not the 3.6 m floor-to-floor height.
	lobby_housing.position=Vector3(source.x,3.2-float(pin.size[1]),source.z)
	for mesh: MeshInstance3D in lobby_housing.find_children("*","MeshInstance3D",true,false):
		mesh.layers=2;mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
		for surface in mesh.mesh.get_surface_count():
			var original: Material=mesh.get_active_material(surface)
			if original is StandardMaterial3D and original.emission_enabled:
				var material: StandardMaterial3D=original.duplicate()
				material.emission=light.light_color
				material.emission_energy_multiplier=float(source.energy)*6.0
				mesh.set_surface_override_material(surface,material)
	world.add_child(lobby_housing)
	# Place the light just below the emitting underside, outside its own mesh.
	light.position=lobby_housing.position-Vector3.UP*.03
	light.set_meta("fixture_kind","suspended_fluorescent")
	light.set_meta("fixture_housing",lobby_housing.get_path())

func update_viewmodel() -> void:
	# The normal viewmodel copy predates omni projectors. Match the source here
	# without invalidating the reference bake.
	for copies in world.viewmodel_lighting.targets:
		for i in world.viewmodel_lighting.slots.size():
			var source: Light3D=world.viewmodel_lighting.slots[i].source
			if source is OmniLight3D:copies[i].omni.light_projector=source.light_projector

func observe() -> Dictionary:
	# Zero means no additional subdivided meshes, not that shadows are disabled.
	var result: Dictionary={"fixtures":fixtures,"fixture_count":fixtures.size(),"emitters":lights.size(),"shadow_meshes":0,"shadow_triangles":0,"shadow_geometry":"original_meshes","profile":{"points":1,"spacing_m":0.0,"energy_scale_from_v46":.7,"distance_attenuation":1.0,"size_m":.08,"shadow_bias":.025,"shadow_normal_bias":.02,"shadow_filter":"medium PCSS; lobby filtered PCF","projector":"256x128 downward cosine"},"indirect":"unchanged v46; preview, not a matching rebake"}
	if is_instance_valid(lobby_housing):
		var light: OmniLight3D=world.get_node(LOBBY_LIGHT+"_Diffuse")
		result.lobby={"source":LOBBY_LIGHT,"housing":str(lobby_housing.get_path()),"housing_position":str(lobby_housing.position),"light_position":str(light.position),"energy":light.light_energy,"shadow":light.shadow_enabled,"light_size":light.light_size,"cabin_lights_unchanged":CABIN_LIGHTS}
	return result

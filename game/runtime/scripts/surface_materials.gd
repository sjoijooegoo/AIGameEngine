extends RefCounted
## One authored material set. Roles and revisions are pinned in pbr_textures.json.
static func apply(world: Node3D) -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/pbr_textures.json"))
	var pins: Dictionary=data.pins
	# Preserve v24's concrete ceiling from exploration.make_materials(); the
	# later Agency tile override changed the authored look of every room.
	var mapping: Dictionary={"wood":"wood","woodlight":"wood","wallwood":"wood","stairs":"floor","lino":"floor","metal":"steel_panels","grate":"steel_panels","office":"office_carpet"}
	var roughness: Dictionary={"tile":.53,"kitchen":.48,"wood":.72,"woodlight":.72,"wallwood":.78,"concrete":.88,"stairs":.86,"lino":.83,"asphalt":.96,"office":.96,"metal":.56,"grate":.62}
	for key in roughness:
		var material: StandardMaterial3D=world.materials[key]
		material.roughness=roughness[key]
		material.metallic=0.0
		material.metallic_specular=.4
		if mapping.has(key):
			var roles: Dictionary=pins[mapping[key]]
			if roles.has("normal"):
				material.normal_enabled=true
				material.normal_texture=load(roles.normal.resource)
				material.normal_scale=.75 if key in ["wood","woodlight","wallwood","office"] else .55
			if key=="office":
				material.albedo_texture=load(roles.albedo.resource)
				material.albedo_color=Color("afa096")
			if key in ["metal","grate"]:material.metallic=.55
		var mask_key: String={"woodlight":"wood","wallwood":"wood","stairs":"floor","lino":"floor","metal":"steel_panels","grate":"steel_panels"}.get(key,key)
		if pins.has(mask_key) and pins[mask_key].has("orm"):
			var orm: Texture2D=load(pins[mask_key].orm.resource)
			material.roughness=1.0
			material.roughness_texture=orm
			material.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			if key in ["metal","grate"]:
				material.metallic=1.0
				material.metallic_texture=orm
				material.metallic_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	for key in ["wall","wallgreen","lower_wall"]:
		var material: ShaderMaterial=world.materials[key]
		material.set_shader_parameter("detail_texture",load(pins.plaster.detail.resource))
		material.set_shader_parameter("detail_strength",.14)
		material.set_shader_parameter("normal_detail",load(pins.office_wall.normal.resource))
		material.set_shader_parameter("normal_strength",.22)
		material.set_shader_parameter("base_roughness",.86 if key!="lower_wall" else .68)
		material.set_shader_parameter("paint_tint",Color("b1b3a1") if key!="lower_wall" else Color("5c7164"))

shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, ambient_light_disabled;
uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness_value = 0.85;
uniform float metallic_value = 0.0;
uniform float specular_value = 0.4;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metallic_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0,1.0,0.0,0.0);
uniform vec4 metallic_channel = vec4(0.0,0.0,1.0,0.0);
uniform bool has_roughness = false;
uniform bool has_metallic = false;
uniform bool triplanar = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform float normal_strength = 1.0;
instance uniform vec3 indirect_front = vec3(0.0);
instance uniform vec3 indirect_back = vec3(0.0);
instance uniform vec3 door_axis = vec3(0.0,0.0,1.0);
varying vec3 world_normal;
varying vec3 world_position;
void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
vec4 surface_sample(sampler2D tex, vec2 uv) {
	vec4 color = texture(tex,uv);
	if (triplanar) {
		vec3 w = pow(abs(normalize(world_normal)),vec3(4.0));w /= max(w.x+w.y+w.z,0.0001);
		vec3 p = world_position * uv_scale + uv_offset;
		color = texture(tex,p.zy)*w.x + texture(tex,p.xz)*w.y + texture(tex,p.xy)*w.z;
	}
	return color;
}
void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	vec4 color = surface_sample(base_map,uv);
	ALBEDO = color.rgb * tint.rgb;
	ROUGHNESS = roughness_value; METALLIC = metallic_value; SPECULAR = specular_value;
	if (has_roughness) { ROUGHNESS *= dot(surface_sample(roughness_map,uv),roughness_channel); }
	if (has_metallic) { METALLIC *= dot(surface_sample(metallic_map,uv),metallic_channel); }
	if (has_normal && !triplanar) { NORMAL_MAP=texture(normal_map,uv).rgb; NORMAL_MAP_DEPTH=normal_strength; }
	// Occlusion-tested probe irradiance replaces unoccluded global ambient
	// and native tetrahedral interpolation across opposite sides of a door.
	float facing = dot(normalize(world_normal),door_axis);
	// Edge/reveal faces must not average bright-room irradiance into the
	// closed dark side. Use the conservative shared component at the rim.
	vec3 irradiance = facing > 0.5 ? indirect_front : (facing < -0.5 ? indirect_back : min(indirect_front,indirect_back));
	EMISSION = ALBEDO * irradiance * (1.0-METALLIC);
}

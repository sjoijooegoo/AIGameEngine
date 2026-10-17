shader_type spatial;
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 paint_tint : source_color = vec4(0.9, 0.93, 0.85, 1.0);
uniform float floor_height = 3.6;
uniform sampler2D detail_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_strength = 0.0;
uniform float base_roughness = 0.9;
uniform sampler2D normal_detail : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength = 0.22;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	float u = abs(world_normal.x) > abs(world_normal.z) ? world_position.z : world_position.x;
	float h = mod(world_position.y, floor_height);
	vec2 uv = vec2(u / 2.0, clamp(1.0 - h / 3.2, 0.01, 0.999));
	float grain = texture(detail_texture, vec2(u, world_position.y) * 2.0).r - 0.5;
	ALBEDO = texture(base_texture, uv).rgb * paint_tint.rgb * (1.0 + grain * detail_strength);
	ROUGHNESS = clamp(base_roughness + grain * detail_strength, 0.45, 1.0);
	// Derive the tangent frame from the same world-aligned coordinates as the
	// plaster detail. Imported mesh UV/tangents need not match this projection.
	vec2 detail_uv = vec2(u, world_position.y) * 2.0;
	vec3 dp1 = dFdx(VERTEX), dp2 = dFdy(VERTEX);
	vec2 duv1 = dFdx(detail_uv), duv2 = dFdy(detail_uv);
	vec3 p2 = cross(dp2, NORMAL), p1 = cross(NORMAL, dp1);
	vec3 t = p2 * duv1.x + p1 * duv2.x;
	vec3 b = p2 * duv1.y + p1 * duv2.y;
	float basis_length = max(dot(t,t),dot(b,b));
	// Godot imports normal maps as two-channel RG/BC5 textures. Reconstruct
	// positive Z instead of reading the absent blue channel as -1.
	vec2 normal_xy = (texture(normal_detail,detail_uv).rg * 2.0 - 1.0) * normal_strength;
	vec3 detail_normal = vec3(normal_xy,sqrt(max(1.0-dot(normal_xy,normal_xy),0.0)));
	if (basis_length > 0.00000001) {
		float scale = inversesqrt(basis_length);
		NORMAL = normalize(mat3(t*scale,b*scale,NORMAL) * detail_normal);
	}
}

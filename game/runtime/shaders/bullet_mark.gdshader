shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform vec4 mark_color : source_color = vec4(.12, .10, .08, 1.);
void fragment() {
	vec2 p = (UV - .5) * 2.;
	float edge = length(p) + .12 * sin(p.x * 34.) * sin(p.y * 29.);
	ALBEDO = mark_color.rgb;
	ROUGHNESS = 1.;
	ALPHA = (1. - smoothstep(.35, .95, edge)) * .9;
}

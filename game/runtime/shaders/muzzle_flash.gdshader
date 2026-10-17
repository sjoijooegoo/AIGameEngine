shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	vec2 p = (UV - .5) * 2.;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float lobe = pow(abs(sin(angle * 3. + .4)), 12.);
	float mask = exp(-r * 11.) + lobe * exp(-r * 5.) * .7;
	vec3 hot = mix(vec3(1., .25, .035), vec3(1., .9, .55), exp(-r * 7.));
	ALBEDO = hot * 3.;
	ALPHA = clamp(mask * 3., 0., 1.) * (1. - smoothstep(.65, 1., r));
}

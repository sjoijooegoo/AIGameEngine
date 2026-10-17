shader_type canvas_item;
render_mode unshaded;
uniform sampler2D rendered_scene : hint_screen_texture, filter_linear;
void fragment() {
	vec3 c = texture(rendered_scene, SCREEN_UV).rgb;
	float luma = dot(c, vec3(.2126,.7152,.0722));
	c = mix(vec3(luma), c, .96);
	vec2 d = SCREEN_UV * 2.0 - 1.0;
	float vignette = 1.0 - smoothstep(.55, 1.45, length(d)) * .10;
	float grain = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898,78.233))) * 43758.5453) - .5;
	COLOR = vec4(max(c * vignette + grain / 480.0, vec3(0.0)), 1.0);
}

shader_type canvas_item;
void fragment() {
	vec2 p = UV;
	float glow = exp(-length((p - vec2(0.74,0.5))*vec2(1.1,1.7))*4.0);
	float grain = fract(sin(dot(floor(FRAGCOORD.xy),vec2(12.9898,78.233)))*43758.5453);
	vec3 color = mix(vec3(0.018,0.029,0.025),vec3(0.085,0.12,0.086),glow);
	color += (grain-0.5)*0.012;
	color *= 0.65+0.35*pow(16.0*p.x*p.y*(1.0-p.x)*(1.0-p.y),0.16);
	COLOR=vec4(color,1.0);
}

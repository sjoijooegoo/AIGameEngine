shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform bool cloud = false;
varying float seed;
varying float head;
varying float burst;
void vertex() { seed = INSTANCE_CUSTOM.x; head = INSTANCE_CUSTOM.y; burst = INSTANCE_CUSTOM.z; }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7)) + seed*71.3)*43758.5453); }
void fragment() {
	vec2 p = (UV-.5)*2.;
	float r = length(p);
	float edge = cloud ? r + .12*sin(atan(p.y,p.x)*7.+seed*21.) + .075*sin(p.x*13.+p.y*9.) : length(vec2(p.x,p.y*.95));
	float radial = 1.-smoothstep(cloud ? .12 : .45,1.,edge);
	float grain = cloud ? mix(.62,1.,hash21(floor(UV*26.))) : 1.;
	float core = 1.-smoothstep(.02,.58,r);
	float shape = cloud ? (radial*(.54+.46*grain) + core*.22) : radial;
	float rim = smoothstep(.04,.82,shape);
	float density = mix(.72,1.0,1.-smoothstep(0.,1.,r)) + head*.08 + burst*.16;
	ALBEDO = COLOR.rgb * mix(.52,1.08,density);
	EMISSION = COLOR.rgb * (.025 + burst*.035);
	ROUGHNESS = .88;
	ALPHA = COLOR.a * shape * grain * rim;
}

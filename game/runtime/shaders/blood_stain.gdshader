shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
varying float seed;
void vertex() { seed = INSTANCE_CUSTOM.x; }
void fragment() {
	vec2 p=(UV-.5)*2.;
	float edge=length((p+vec2(.08,-.03))/vec2(.67,.43))+.14*sin(p.x*17.+seed*9.)*sin(p.y*13.-seed*15.);
	float core=1.-smoothstep(.76,1.,edge);
	float flecks=0.;
	for(int i=0;i<7;i++) {
		float angle=float(i)*2.399+seed*6.28;
		vec2 center=vec2(cos(angle),sin(angle))*(.58+.18*sin(float(i)*4.+seed));
		flecks=max(flecks,1.-smoothstep(.025,.085,length(p-center)));
	}
	ALBEDO=COLOR.rgb*mix(.65,1.,core);
	ROUGHNESS=.82;
	ALPHA=COLOR.a*max(core,flecks*.75);
}

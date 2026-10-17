shader_type canvas_item;
uniform float strength=0.;
uniform vec2 direction=vec2(0.,1.);
uniform float grabbed=0.;
uniform float dead=0.;
void fragment(){
	vec2 p=(UV-.5)*2.;
	float radius=length(p);
	vec2 aim=vec2(direction.x,-direction.y);
	float facing=.35+.65*max(0.,dot(normalize(p+vec2(.001)),normalize(aim+vec2(.001))));
	float edge=smoothstep(.30,1.25,radius);
	float alpha=edge*(strength*.55*facing+grabbed*.09)+dead*.24;
	COLOR=vec4(.32,.025,.015,clamp(alpha,0.,.6));
}

shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_image : hint_screen_texture, filter_linear_mipmap;
uniform float title_screen = 0.0;
void fragment(){
 vec3 scene=textureLod(screen_image,SCREEN_UV,mix(1.5,.35,title_screen)).rgb;
 float lum=dot(scene,vec3(.2126,.7152,.0722));
 scene=mix(vec3(lum)*vec3(.86,.95,.83),scene,.45);
 float shade=mix(.68,mix(.96,.14,smoothstep(.24,.90,SCREEN_UV.x)),title_screen);
 vec3 color=mix(scene,vec3(.037,.056,.050),shade);
 float grain=fract(sin(dot(floor(FRAGCOORD.xy),vec2(12.9898,78.233)))*43758.5453)-.5;
 float vignette=smoothstep(.3,1.3,length(SCREEN_UV*2.-1.));
 COLOR=vec4(color*(1.-vignette*.25)+grain*.014,1.0);
}

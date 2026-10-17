shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
uniform sampler2D grime_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 glass_tint : source_color = vec3(0.32, 0.46, 0.42);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    // Sample only the pane interior of the inspected Source window image;
    // real frame members are separate geometry, not painted into the glass.
    vec2 pane_uv = mix(vec2(0.055,0.075),vec2(0.455,0.455),fract(UV));
    vec3 dirt = texture(grime_texture,pane_uv).rgb;
    float grime = clamp(1.0-dot(dirt,vec3(0.333)),0.0,1.0);
    float edge = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
    float stripe = 1.0-smoothstep(0.022,0.034,abs(mod(world_position.y,3.6)-1.55));
    ALBEDO = mix(glass_tint*(0.75+0.4*dirt),vec3(0.63,0.68,0.61),stripe*.8);
    ALPHA = clamp(0.18+grime*.17+edge*.22+stripe*.20,0.18,0.62);
    ROUGHNESS = 0.26+grime*.3;
    METALLIC = 0.05;
    SPECULAR = 0.65;
}

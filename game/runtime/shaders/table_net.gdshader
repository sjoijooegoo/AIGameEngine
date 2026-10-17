shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 grid = abs(fract(world_position.yz / 0.015) - 0.5);
    float strand = max(step(0.44, grid.x), step(0.44, grid.y));
    ALBEDO = vec3(0.36, 0.38, 0.33);
    ROUGHNESS = 0.95;
    ALPHA = strand;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}

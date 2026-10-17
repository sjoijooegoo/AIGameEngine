shader_type spatial;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float roller_height;
varying float world_height;
void vertex() { world_height=(MODEL_MATRIX*vec4(VERTEX,1.0)).y; }
void fragment() {
    if (world_height>roller_height) { discard; }
    ALBEDO=texture(albedo_texture,UV).rgb;
    ROUGHNESS=0.72;
    METALLIC=0.25;
}

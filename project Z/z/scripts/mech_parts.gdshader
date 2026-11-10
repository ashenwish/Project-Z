shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D image : source_color, filter_nearest;
uniform sampler2D parts : filter_nearest;
uniform vec3 broken = vec3(0.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
void fragment() {
    vec4 c = texture(image, UV);
    if (c.a < 0.5 || dot(texture(parts, UV).rgb, broken) > 0.5) { discard; }
    int x = int(FRAGCOORD.x);
    int y = int(FRAGCOORD.y);
    int low = ((x & 1) ^ (y & 1)) * 2 + (y & 1);
    int high = (((x >> 1) & 1) ^ ((y >> 1) & 1)) * 2 + ((y >> 1) & 1);
    if (opacity < (float(low * 4 + high) + 0.5) / 16.0) { discard; }
    ALBEDO = c.rgb;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}

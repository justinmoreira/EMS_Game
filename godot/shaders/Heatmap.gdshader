shader_type canvas_item;

// Overall opacity of the heatmap overlay.
uniform float alpha : hint_range(0.0, 1.0) = 0.5;

// Convert a terrain-influence-factor in [0,1] to a colour.
// tif = 0  →  blocked  (dark red)
// tif = 1  →  clear LOS (green)
vec3 tif_to_color(float tif) {
    // Map tif to hue: 0 = red (0°), 1 = green (120° = 1/3 of the wheel)
    float hue = tif * (1.0 / 3.0);
    float h6  = hue * 6.0;
    float x   = 1.0 - abs(mod(h6, 2.0) - 1.0);
    vec3 rgb;
    if      (h6 < 1.0) rgb = vec3(1.0, x,   0.0);
    else if (h6 < 2.0) rgb = vec3(x,   1.0, 0.0);
    else               rgb = vec3(0.0, 1.0, x  );
    // Blend from a dark-red "blocked" tint toward the full HSV colour.
    return mix(vec3(0.5, 0.02, 0.02), rgb, tif);
}

void fragment() {
    // Map UV [0,1] → [-1,1] (normalised to the heatmap radius).
    vec2  norm = UV * 2.0 - 1.0;
    float dist = length(norm);

    if (dist > 1.0) {
        // Outside the circle — fully transparent.
        // Avoid early return (not supported on all Godot backends).
        COLOR = vec4(0.0);
    } else {
        // TEXTURE is the baked TIF image (red channel stores the [0,1] value).
        float tif = texture(TEXTURE, UV).r;
        vec3  col = tif_to_color(tif);

        // Mask to the circle with a 3% anti-aliasing fringe at the boundary.
        float mask = 1.0 - smoothstep(0.97, 1.0, dist);
        COLOR = vec4(col, alpha * mask);
    }
}

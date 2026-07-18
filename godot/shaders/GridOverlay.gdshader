shader_type canvas_item;

const int MAX_LEVELS = 8; // Has to match in MapGridOverlay.gd

uniform float zoom = 1.0;
uniform vec2 offset = vec2(0.0);
uniform float aspect_ratio = 1.0;
uniform vec4 line_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);

uniform int level_count = 0;
uniform float level_cell_uv[MAX_LEVELS];
uniform float level_width_px[MAX_LEVELS];
uniform float level_alpha[MAX_LEVELS];

// Fade the grid out past the map border
uniform float edge_fade_start = -0.05;
uniform float edge_fade_end = 0.26;
uniform float edge_fade_max : hint_range(0.0, 1.0) = 0.85;

float line_mask(vec2 uv, float cell, float px, float width_px) {
    vec2 g = mod(uv, cell);
    vec2 dist_to_line = min(g, vec2(cell) - g);
    float d = min(dist_to_line.x, dist_to_line.y);
    float half_w = 0.5 * width_px * px;
    return 1.0 - smoothstep(half_w, half_w + px, d);
}

void fragment() {
    vec2 uv = UV - 0.5;

    if (aspect_ratio > 1.0) {
        uv.x *= aspect_ratio;
    } else {
        uv.y *= (1.0 / aspect_ratio);
    }

    vec2 map_uv = (uv * zoom) + 0.5 + offset;

    // No bounds clip: the grid is infinite
    float px = fwidth(map_uv.x);
    float a = 0.0;
    for (int i = 0; i < level_count; i++) {
        a = max(a, line_mask(map_uv, level_cell_uv[i], px, level_width_px[i]) * level_alpha[i]);
    }

    // Sink the lines into the fog along with the fake terrain
    vec2 over = max(-map_uv, map_uv - 1.0);
    float edge_sd = max(over.x, over.y);
    a *= 1.0 - smoothstep(edge_fade_start, edge_fade_end, edge_sd) * edge_fade_max;

    COLOR = vec4(line_color.rgb, a * line_color.a);
}

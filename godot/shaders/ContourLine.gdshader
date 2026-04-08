shader_type canvas_item;

uniform sampler2D height_map;

// ── Elevation coloring ─────────────────────────────
uniform vec4 color_low  : source_color;  // green
uniform vec4 color_mid  : source_color;  // tan
uniform vec4 color_high : source_color;  // white

uniform vec4 water_color : source_color; // blue

uniform float max_height = 500.0;
uniform float sea_level  = 100.0;
uniform float mid_point  = 0.6;

// ── Contours ───────────────────────────────────────
uniform float contour_interval = 50.0;
uniform float line_thickness = 1.0;
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);

void fragment() {
    float h = texture(height_map, UV).r;

    // Normalize height
    float t = h / max_height;

    vec3 base_color;

    // ── WATER ──────────────────────────────────────
    if (h < sea_level) {
        float water_t = h / sea_level;
        base_color = mix(water_color.rgb * 0.7, water_color.rgb, water_t);
    }
    else {
        // Remap land height above sea level → 0–1
        float land_t = (h - sea_level) / (max_height - sea_level);

        // ── 3-COLOR TERRAIN ────────────────────────
        if (land_t < mid_point) {
            float local_t = land_t / mid_point;
            base_color = mix(color_low.rgb, color_mid.rgb, local_t);
        } else {
            float local_t = (land_t - mid_point) / (1.0 - mid_point);
            base_color = mix(color_mid.rgb, color_high.rgb, local_t);
        }
    }

    // ── CONTOUR LINES ─────────────────────────────
    float f = abs(fract(h / contour_interval - 0.5) - 0.5);
    float df = fwidth(h / contour_interval);
    float g = smoothstep(df * line_thickness, 0.0, f);

    vec3 final_color = mix(base_color, line_color.rgb, g);

    COLOR = vec4(final_color, 1.0);
}
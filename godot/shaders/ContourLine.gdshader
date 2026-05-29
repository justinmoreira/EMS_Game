shader_type canvas_item;

uniform sampler2D height_map;

uniform float zoom = 1.0;
uniform vec2  offset = vec2(0.0, 0.0);
uniform float aspect_ratio = 1.0;

// ── Elevation coloring ─────────────────────────────
uniform vec4 color_low  : source_color;  // green
uniform vec4 color_mid  : source_color;  // tan
uniform vec4 color_high : source_color;  // white

uniform vec4 water_color : source_color; // blue

uniform float max_height = 500.0;
uniform float sea_level  = 100.0;
uniform float low_point  = 0.3;
uniform float mid_point  = 0.6;
uniform float high_point  = 0.85;

uniform bool gray_mode = false;
uniform vec4 gray_mode_color : source_color;

// Contours
uniform float contour_interval = 50.0;
uniform float line_thickness = 1.0;
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);

void fragment() {
	vec2 uv = UV - vec2(0.5);

    // Match HeightMap.gdshader's contain logic so world_uv_to_screen (in
    // BaseLevel.gd) and the rendered terrain agree on where world_uv maps to.
    if (aspect_ratio > 1.0) {
        uv.x *= aspect_ratio;
    } else {
        uv.y *= (1.0 / aspect_ratio);
    }

    // Apply zoom and pan offset
    vec2 raw_map_uv = uv * zoom + vec2(0.5) + offset;
    bool in_bounds = raw_map_uv.x >= 0.0 && raw_map_uv.x <= 1.0
                  && raw_map_uv.y >= 0.0 && raw_map_uv.y <= 1.0;

    // Clamp for the texture sample only; out-of-bounds is overwritten with the
    // void color at the end so the clamped edge row never smears outward.
    vec2 map_uv = clamp(raw_map_uv, vec2(0.0), vec2(1.0));

    float h = texture(height_map, map_uv).r;

    vec3 base_color;
    if (gray_mode) {
        base_color = gray_mode_color.rgb;
    }
    // WATER
    else if (h < sea_level) {
        base_color = water_color.rgb;
    }
    else {
        float land_t = (h - sea_level) / (max_height - sea_level);
        if (land_t < low_point) {
            base_color = color_low.rgb;
        } else if (land_t < mid_point) {
            base_color = color_low.rgb * 1.3;
        } else if (land_t < high_point) {
            base_color = color_mid.rgb;
        } else {
            base_color = color_high.rgb;
        }
    }

    // CONTOUR LINES
    float f  = abs(fract(h / contour_interval - 0.5) - 0.5);
    float df = fwidth(h / contour_interval);
    float g  = smoothstep(df * line_thickness, 0.0, f);
    vec3 final_color = mix(base_color, line_color.rgb, g);

    // Void outside the map — matches the app background (#0a0a0a) instead of
    // smearing the clamped edge pixels when panned/zoomed past the heightmap.
    if (!in_bounds) {
        final_color = vec3(0.039);
    }

    COLOR = vec4(final_color, 1.0);
}
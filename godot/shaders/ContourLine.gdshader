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
uniform float high_point  = 0.75;

uniform bool gray_mode = false;
uniform vec4 gray_mode_color : source_color;

// Contours
uniform float contour_interval = 50.0;
uniform float line_thickness = 1.0;
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);

// Color blending & relief shading
uniform float blend_softness : hint_range(0.0, 0.3) = 0.08;
uniform float shore_blend = 6.0;
uniform float hillshade_strength : hint_range(0.0, 1.0) = 0.35;
uniform float hillshade_slope_scale : hint_range(0.0, 1.0) = 0.08;
uniform vec3 light_dir = vec3(-0.6, -0.6, 0.7);
uniform float elevation_light : hint_range(0.0, 0.5) = 0.3;
uniform float water_depth_shading : hint_range(0.0, 1.0) = 0.45;
uniform float water_shallow_light : hint_range(0.0, 1.0) = 0.25;
uniform float water_depth_range = 35.0;
uniform float terrace_shading : hint_range(0.0, 0.5) = 0.1;

vec3 land_color(float land_t) {
	vec3 c = color_low.rgb;
	c = mix(c, color_low.rgb * 1.3,
		smoothstep(low_point - blend_softness, low_point + blend_softness, land_t));
	c = mix(c, color_mid.rgb,
		smoothstep(mid_point - blend_softness, mid_point + blend_softness, land_t));
	c = mix(c, color_high.rgb,
		smoothstep(high_point - blend_softness, high_point + blend_softness, land_t));
	return c;
}

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

    // Contour-band coordinate, computed unconditionally so fwidth()
    // stays outside divergent control flow
    float band = h / contour_interval;
    float band_df = fwidth(band);

    vec3 base_color;
    if (gray_mode) {
        base_color = gray_mode_color.rgb;
    }
    else {
        // Water
        float depth_t = sqrt(clamp((sea_level - h) / max(water_depth_range, 0.001), 0.0, 1.0));
        vec3 water = water_color.rgb
            * mix(1.0 + water_shallow_light, 1.0 - water_depth_shading, depth_t);

        // Land
        float land_t = clamp((h - sea_level) / (max_height - sea_level), 0.0, 1.0);
        vec3 land = land_color(land_t);

        // Lighter high ground/darker low ground for a sense of depth
        land *= 1.0 + (land_t - 0.35) * elevation_light;

        // Hill Shading
        vec2 texel = 1.0 / vec2(textureSize(height_map, 0));
        float h_l = texture(height_map, clamp(map_uv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r;
        float h_r = texture(height_map, clamp(map_uv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r;
        float h_t = texture(height_map, clamp(map_uv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r;
        float h_b = texture(height_map, clamp(map_uv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r;
        vec2 grad = vec2(h_r - h_l, h_b - h_t) * 0.5;

        vec3 normal = normalize(vec3(-grad * hillshade_slope_scale, 1.0));
        vec3 light = normalize(light_dir);
        // Normalized so flat ground stays at its base color
        float relief = dot(normal, light) / max(light.z, 0.001);
        land *= mix(1.0, clamp(relief, 0.0, 1.6), hillshade_strength);

        float terrace_aa = smoothstep(0.5, 0.15, band_df);
        land *= 1.0 + (fract(band) - 0.5) * terrace_shading * terrace_aa;

        // Shoreline crossfade
        float shore_t = smoothstep(sea_level - shore_blend, sea_level + shore_blend, h);
        base_color = mix(water, land, shore_t);
    }

    // CONTOUR LINES
    float f  = abs(fract(band - 0.5) - 0.5);
    float g  = smoothstep(band_df * line_thickness, 0.0, f);
    vec3 final_color = mix(base_color, line_color.rgb, g);

    // Void outside the map — matches the app background (#0a0a0a) instead of
    // smearing the clamped edge pixels when panned/zoomed past the heightmap.
    if (!in_bounds) {
        final_color = vec3(0.039);
    }

    COLOR = vec4(final_color, 1.0);
}

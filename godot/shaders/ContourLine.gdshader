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

// ── Fake terrain past the border ────────────────────
// Beyond world_uv 0..1, value-noise fbm continues the landscape under the
// EdgeFog overlay
uniform float fake_terrain_scale = 3.75; // noise cycles per map width
uniform float fake_height_min = 0.0;
uniform float fake_height_max = 500.0;
uniform float fake_blend_dist = 0.06; // real→fake crossfade width past the border

// Desaturation, contour-line fade, and blur all ride one ramp past the border
uniform float fake_desat_start = -0.05;
uniform float fake_desat_end = 0.26;
uniform float fake_desat_max : hint_range(0.0, 1.0) = 0.7;
uniform float fake_line_fade_max : hint_range(0.0, 1.0) = 0.85;
// false = hard-cut contour lines at the border instead of fading them out
uniform bool fake_contour_lines = false;
// Blur tap radius at full ramp (uv) and how much hillshade relief flattens
uniform float fake_blur_radius = 0.1;
uniform float fake_relief_fade : hint_range(0.0, 1.0) = 0.8;

#include "res://shaders/ValueNoise.gdshaderinc"

float fake_height(vec2 uv) {
	// Renormalize fbm (amplitudes sum to 0.875) to ~0..1 before remapping
	float n = fbm(uv * fake_terrain_scale + vec2(37.0, 61.0)) / 0.875;
	return mix(fake_height_min, fake_height_max, clamp(n, 0.0, 1.0));
}

// Composite height field
float terrain_height(vec2 raw_uv) {
	float real_h = texture(height_map, clamp(raw_uv, vec2(0.0), vec2(1.0))).r;
	vec2 over = max(-raw_uv, raw_uv - vec2(1.0));
	float d = max(max(over.x, over.y), 0.0);
	return mix(real_h, fake_height(raw_uv), smoothstep(0.0, fake_blend_dist, d));
}

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

    // Ramp progress past the border (blur, line fade, and desaturation)
    vec2 over = max(-raw_map_uv, raw_map_uv - 1.0);
    float edge_sd = max(over.x, over.y);
    float edge_t = smoothstep(fake_desat_start, fake_desat_end, edge_sd);

    // Blur of heightfield
    float blur_r = edge_t * fake_blur_radius;
    float diag_r = blur_r * 0.7071;
    float h = (terrain_height(raw_map_uv)
        + terrain_height(raw_map_uv + vec2(blur_r, 0.0))
        + terrain_height(raw_map_uv - vec2(blur_r, 0.0))
        + terrain_height(raw_map_uv + vec2(0.0, blur_r))
        + terrain_height(raw_map_uv - vec2(0.0, blur_r))
        + terrain_height(raw_map_uv + vec2(diag_r, diag_r))
        + terrain_height(raw_map_uv - vec2(diag_r, diag_r))
        + terrain_height(raw_map_uv + vec2(diag_r, -diag_r))
        + terrain_height(raw_map_uv - vec2(diag_r, -diag_r))) / 9.0;

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
        float h_l = terrain_height(raw_map_uv - vec2(texel.x, 0.0));
        float h_r = terrain_height(raw_map_uv + vec2(texel.x, 0.0));
        float h_t = terrain_height(raw_map_uv - vec2(0.0, texel.y));
        float h_b = terrain_height(raw_map_uv + vec2(0.0, texel.y));
        vec2 grad = vec2(h_r - h_l, h_b - h_t) * 0.5;
        grad *= 1.0 - edge_t * fake_relief_fade;

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
    g *= 1.0 - edge_t * fake_line_fade_max;
    if (!fake_contour_lines) {
        // Soft cut at the border so the last real row doesn't alias
        g *= 1.0 - smoothstep(0.0, 0.004, edge_sd);
    }
    vec3 final_color = mix(base_color, line_color.rgb, g);

    // Desaturate in step with the fog
    float luma = dot(final_color, vec3(0.2126, 0.7152, 0.0722));
    final_color = mix(final_color, vec3(luma), edge_t * fake_desat_max);

    COLOR = vec4(final_color, 1.0);
}

shader_type canvas_item;

// Fog-of-war veil past the map border, drawn as an overlay ABOVE the MGRS
// grid (see EdgeFogOverlay.gd) so the grid lines and the fake terrain fade
// into the haze together. One ramp from inside the border out to fog_end,
// capped below full opacity. Distances are in map-uv units, so the fog pans
// and zooms with the terrain. Camera uniforms and the contain logic must
// match ContourLine.gdshader

uniform float zoom = 1.0;
uniform vec2 offset = vec2(0.0);
uniform float aspect_ratio = 1.0;

uniform vec4 fog_color : source_color = vec4(0.03, 0.037, 0.05, 1.0);
// fog_start leads the ContourLine/GridOverlay
// fog creeps onto the real map's outer strip while the map keeps its color and lines there
uniform float fog_start = -0.2; // ramp begins inside the map, creeping over it
uniform float fog_end = 0.2;    // ramp reaches peak thickness here
uniform float fog_max_opacity : hint_range(0.0, 1.0) = 0.92; // never fully opaque
uniform float fog_noise_scale = 9.0;
uniform float fog_wisp : hint_range(0.0, 0.3) = 0.06; // noise perturbing the fog edge
uniform vec2 fog_drift = vec2(0.02, 0.011); // slow cloud drift (uv/sec)

// ── Keepout hatching ────────────────────────────────
// While a unit is dragged (EdgeFogOverlay drives `keepout` 0→1), the area
// outside the AO darkens with diagonal stripes
uniform float keepout : hint_range(0.0, 1.0) = 0.0;
uniform vec4 keepout_color : source_color = vec4(0.03, 0.035, 0.05, 1.0);
uniform float keepout_darken : hint_range(0.0, 1.0) = 0.35; // stripe floor opacity
uniform float keepout_stripe : hint_range(0.0, 1.0) = 0.1;  // extra on dark stripes
uniform float keepout_stripe_px = 48.0; // stripe period in screen pixels

#include "res://shaders/ValueNoise.gdshaderinc"

void fragment() {
    vec2 uv = UV - vec2(0.5);

    if (aspect_ratio > 1.0) {
        uv.x *= aspect_ratio;
    } else {
        uv.y *= (1.0 / aspect_ratio);
    }

    vec2 raw_map_uv = uv * zoom + vec2(0.5) + offset;

    // Signed distance to the map border, negative inside
    vec2 over = max(-raw_map_uv, raw_map_uv - 1.0);
    float edge_sd = max(over.x, over.y);

    // Drifting cloud noise, anchored to map space so it pans with the map
    float n = fbm(raw_map_uv * fog_noise_scale + TIME * fog_drift);

    // Un-wisped ramp progress, fading the noise in so neither the wisps nor
    // the cloud texture pop at the boundary
    float base_t = smoothstep(fog_start, fog_end, edge_sd);

    float wisped = edge_sd + (n - 0.5) * fog_wisp * base_t;
    float fog_t = smoothstep(fog_start, fog_end, wisped) * fog_max_opacity;

    // Strong noise modulation keeps the clouds visible in a near-black fog
    vec3 haze = fog_color.rgb * mix(1.0, 0.6 + 1.2 * n, base_t);
    float fog_a = clamp(fog_t, 0.0, 1.0) * fog_color.a;

    // Keepout layer composited over the fog
    float outside = smoothstep(0.0, 0.003, edge_sd);
    float stripe = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / keepout_stripe_px));
    float k_a = keepout * outside * (keepout_darken + keepout_stripe * stripe);

    float out_a = k_a + fog_a * (1.0 - k_a);
    vec3 out_rgb = keepout_color.rgb * k_a + haze * fog_a * (1.0 - k_a);

    COLOR = vec4(out_rgb / max(out_a, 0.0001), out_a);
}

shader_type canvas_item;

uniform float zoom = 1.0;
uniform vec2 offset = vec2(0.0);
uniform float aspect_ratio = 1.0;
uniform float grid_cell_uv = 0.1953125;
uniform float grid_line_width = 0.002;

void fragment() {
    vec2 uv = UV - 0.5;

    if (aspect_ratio > 1.0) {
        uv.x *= aspect_ratio;
    } else {
        uv.y *= (1.0 / aspect_ratio);
    }

    vec2 transformed_uv = (uv * zoom) + 0.5 + offset;

    if (transformed_uv.x < 0.0 || transformed_uv.x > 1.0 || transformed_uv.y < 0.0 || transformed_uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0);
    } else {
        vec2 grid_uv = mod(transformed_uv, grid_cell_uv);
        vec2 dist_to_line = min(grid_uv, vec2(grid_cell_uv) - grid_uv);
        float scaled_width = grid_line_width * zoom;
        float d = min(dist_to_line.x, dist_to_line.y);
        float line_alpha = 1.0 - smoothstep(0.0, scaled_width, d);
        COLOR = vec4(0.0, 0.0, 0.0, line_alpha * 0.5);
    }
}

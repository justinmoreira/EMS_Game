shader_type canvas_item;

uniform float sensitivity : hint_range(0.0, 2.0) = 1.0;
uniform float zoom = 1.0;
uniform vec2 offset = vec2(0.0);
uniform float aspect_ratio = 1.0;

void fragment() {
    vec2 uv = UV - 0.5;
    
    // CONTAIN LOGIC:
    // If Landscape (Wide): Scale X up to create side bars.
    // If Portrait (Tall): Scale Y up to create top/bottom bars.
    if (aspect_ratio > 1.0) {
        uv.x *= aspect_ratio;
    } else {
        uv.y *= (1.0 / aspect_ratio); // Multiply by inverse to scale UP
    }

    vec2 transformed_uv = (uv * zoom) + 0.5 + offset;

    // Void Color
    if (transformed_uv.x < 0.0 || transformed_uv.x > 1.0 || transformed_uv.y < 0.0 || transformed_uv.y > 1.0) {
        COLOR = vec4(0.05, 0.05, 0.05, 1.0);
    } else {
        float height = texture(TEXTURE, transformed_uv).r;
        vec3 low = vec3(0.0, 1.0, 0.0);
        vec3 high = vec3(1.0, 0.0, 0.0);
        COLOR = vec4(mix(low, high, height * sensitivity), 1.0);
    }
}
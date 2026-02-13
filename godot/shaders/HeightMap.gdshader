shader_type canvas_item;

// This allows you to adjust the intensity in the Inspector
uniform float sensitivity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
    // Sample the grayscale noise texture (stored in COLOR currently)
    float height = texture(TEXTURE, UV).r;
    
    // Logic: Low (0.0) = Green, High (1.0) = Red
    // mix(ColorA, ColorB, factor)
    vec3 low_color = vec3(0.0, 1.0, 0.0); // Pure Green
    vec3 high_color = vec3(1.0, 0.0, 0.0); // Pure Red
    vec3 final_rgb = mix(low_color, high_color, height * sensitivity);
    
    COLOR = vec4(final_rgb, 1.0);
}
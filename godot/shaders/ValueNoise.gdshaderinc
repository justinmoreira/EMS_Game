// Shared value noise for ContourLine.gdshader (fake border terrain) and
// EdgeFog.gdshader (fog clouds)

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

// 3-octave value noise fbm; amplitudes sum to 0.875
float fbm(vec2 p) {
	float amp = 0.5;
	float sum = 0.0;
	for (int i = 0; i < 3; i++) {
		sum += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

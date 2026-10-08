// Hotel pool water: clear turquoise with drifting caustic lines and a little
// sparkle, bent by the world curve like everything else.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

#include "res://shaders/cozy_common.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.16, 0.62, 0.82);
uniform vec3 shallow : source_color = vec3(0.45, 0.88, 0.95);
uniform float alpha = 0.42;
uniform vec2 size = vec2(8.0, 4.0);

varying vec3 wpos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest cell border (soft caustic web).
float caustic(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			o = 0.5 + 0.4 * sin(t + 6.2831 * o);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	float t = TIME;
	VERTEX.y += sin(VERTEX.x * 1.7 + t * 1.6) * 0.02 + cos(VERTEX.z * 2.1 + t * 1.3) * 0.02;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec2 uv = wpos.xz * 0.9;
	float c = caustic(uv, TIME * 0.9);
	float c2 = caustic(uv * 1.7 + 3.1, TIME * 1.2);
	float web = (1.0 - smoothstep(0.0, 0.09, c)) * 0.65 + (1.0 - smoothstep(0.0, 0.06, c2)) * 0.35;
	// Lighter towards the edges (shallow-looking rim).
	vec2 e = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.75, 1.0, max(e.x, e.y));
	vec3 col = mix(deep, shallow, edge * 0.7 + 0.15);
	col = mix(col, vec3(1.0), web * 0.45);
	ALBEDO = col;
	ALPHA = clamp(alpha + web * 0.2 + edge * 0.12, 0.0, 1.0);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	EMISSION = col * 0.08 + vec3(web * 0.08);
}

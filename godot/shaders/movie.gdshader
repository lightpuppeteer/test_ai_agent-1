shader_type spatial;
// The cinema screen: three tiny procedural "movies".
// mode 0: idle (curtain glow) · 1: horror · 2: comedy · 3: drama
render_mode unshaded, cull_disabled;

#include "res://shaders/noise.gdshaderinc"

uniform int mode = 0;
uniform float t = 0.0;

float circle(vec2 p, vec2 c, float r) { return smoothstep(r, r - 0.01, length(p - c)); }
float box(vec2 p, vec2 c, vec2 h) { vec2 d = abs(p - c) - h; return smoothstep(0.01, 0.0, max(d.x, d.y)); }

vec3 horror(vec2 uv) {
	vec3 col = mix(vec3(0.02, 0.02, 0.06), vec3(0.08, 0.06, 0.16), uv.y);
	// moon
	col += vec3(0.9, 0.9, 0.8) * circle(uv, vec2(0.8, 0.78), 0.07) * 0.8;
	// house silhouette with a lit attic window
	float house = box(uv, vec2(0.38, 0.28), vec2(0.18, 0.2));
	float roof = step(uv.y, 0.66 - abs(uv.x - 0.38) * 1.1) * step(0.47, uv.y) * step(abs(uv.x - 0.38), 0.22);
	col = mix(col, vec3(0.01), max(house, roof));
	float win = box(uv, vec2(0.38, 0.53), vec2(0.03, 0.035));
	float flick = 0.6 + 0.4 * step(0.3, vnoise(vec2(t * 6.0, 1.0)));
	col = mix(col, vec3(1.0, 0.8, 0.3) * flick, win);
	// the ghost: creeps in, then a jump scare every ~9 s
	float cyc = mod(t, 9.0);
	float scare = smoothstep(7.4, 7.5, cyc) * (1.0 - smoothstep(8.4, 8.6, cyc));
	vec2 gp = mix(vec2(0.72, 0.3 + 0.03 * sin(t * 2.0)), vec2(0.5, 0.45), scare);
	float gs = mix(0.08, 0.38, scare);
	vec2 q = (uv - gp) / gs;
	float ghost = smoothstep(1.0, 0.95, length(vec2(q.x, max(q.y, 0.0)) * vec2(1.0, 0.8))) * step(-1.2 + 0.15 * sin(q.x * 12.0 + t * 5.0), q.y);
	float eyes = circle(q, vec2(-0.3, 0.2), 0.14) + circle(q, vec2(0.3, 0.2), 0.14) + circle(q, vec2(0.0, -0.35), 0.18) * scare;
	col = mix(col, vec3(0.92, 0.95, 1.0), ghost * smoothstep(2.0, 4.0, cyc));
	col = mix(col, vec3(0.0), clamp(eyes, 0.0, 1.0) * ghost * smoothstep(2.0, 4.0, cyc));
	col += vec3(0.6, 0.05, 0.05) * scare * 0.4;
	col *= 0.85 + 0.15 * vnoise(vec2(t * 30.0, uv.y * 4.0));
	return col;
}

vec3 comedy(vec2 uv) {
	vec3 col = mix(vec3(1.0, 0.85, 0.3), vec3(1.0, 0.6, 0.45), uv.y);
	// spinning pizza slice
	vec2 p = uv - vec2(0.5, 0.5);
	float a = t * 1.5;
	p = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * p;
	float slice = step(0.0, p.y) * step(abs(p.x), p.y * 0.6) * step(p.y, 0.22);
	col = mix(col, vec3(1.0, 0.85, 0.4), slice);
	col = mix(col, vec3(0.8, 0.15, 0.1), slice * (circle(p, vec2(0.0, 0.12), 0.025) + circle(p, vec2(0.03, 0.18), 0.02)));
	// bouncing happy faces
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = vec2(0.18 + fi * 0.32, 0.22 + abs(sin(t * 3.0 + fi * 1.7)) * 0.35);
		float face = circle(uv, c, 0.08);
		col = mix(col, vec3(1.0, 0.95, 0.85), face);
		col = mix(col, vec3(0.1), circle(uv, c + vec2(-0.025, 0.02), 0.012) + circle(uv, c + vec2(0.025, 0.02), 0.012));
		float smile = smoothstep(0.006, 0.0, abs(length(uv - c - vec2(0.0, 0.01)) - 0.04)) * step(uv.y, c.y - 0.01);
		col = mix(col, vec3(0.1), smile);
	}
	// confetti
	vec2 g = floor(uv * vec2(24.0, 14.0) + vec2(0.0, t * 3.0));
	float conf = step(0.93, hash12(g));
	col = mix(col, vec3(hash12(g + 1.0), hash12(g + 2.0), hash12(g + 3.0)), conf * 0.8);
	return col;
}

vec3 drama(vec2 uv) {
	vec3 col = mix(vec3(0.12, 0.16, 0.3), vec3(0.3, 0.38, 0.55), uv.y);
	// street lamp glow
	col += vec3(1.0, 0.85, 0.5) * 0.35 * smoothstep(0.35, 0.0, length(uv - vec2(0.68, 0.62)));
	col = mix(col, vec3(0.05), box(uv, vec2(0.68, 0.32), vec2(0.008, 0.3)));
	// a small dog sitting in the rain, looking up
	vec2 d = uv - vec2(0.42, 0.2);
	float dog = box(d, vec2(0.0, 0.0), vec2(0.07, 0.04)) + circle(d, vec2(0.07, 0.07), 0.045)
		+ box(d, vec2(-0.05, -0.05), vec2(0.012, 0.03)) + box(d, vec2(0.05, -0.05), vec2(0.012, 0.03))
		+ box(d, vec2(0.09, 0.11), vec2(0.012, 0.03));
	col = mix(col, vec3(0.04, 0.04, 0.06), clamp(dog, 0.0, 1.0));
	// rain
	vec2 r = vec2(uv.x * 60.0 + uv.y * 6.0, uv.y * 8.0 + t * 6.0);
	float drop = step(0.92, hash12(floor(r))) * smoothstep(0.0, 0.5, fract(r.y));
	col += vec3(0.6, 0.7, 0.9) * drop * 0.35;
	// a heart appears, slowly, in the clouds
	vec2 h = (uv - vec2(0.22, 0.75)) * 6.0;
	float hf = pow(h.x * h.x + h.y * h.y - 1.0, 3.0) - h.x * h.x * h.y * h.y * h.y;
	col = mix(col, vec3(1.0, 0.55, 0.65), step(hf, 0.0) * smoothstep(4.0, 9.0, mod(t, 14.0)) * 0.8);
	return col;
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec3 col;
	if (mode == 1) col = horror(uv);
	else if (mode == 2) col = comedy(uv);
	else if (mode == 3) col = drama(uv);
	else col = mix(vec3(0.25, 0.04, 0.08), vec3(0.45, 0.08, 0.12), 0.5 + 0.5 * sin(uv.x * 60.0)) * 0.6;
	// soft vignette
	col *= 1.0 - 0.35 * pow(length(uv - 0.5) * 1.3, 2.0);
	ALBEDO = col;
	EMISSION = col * 0.6;
}

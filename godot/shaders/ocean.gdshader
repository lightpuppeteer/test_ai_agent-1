shader_type spatial;
// Stylised sea: clear turquoise shallows over the sand, deepening to blue,
// animated foam where the waves lap the beach, and sun glints.
// The wave function is mirrored on the CPU by ocean.gd (buoyancy).
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/noise.gdshaderinc"

uniform float t = 0.0;                                    // synced simulation time
uniform sampler2D ground_height : filter_linear, repeat_disable;
uniform vec4 ground_rect;                                 // x0, z0, size, size
uniform vec4 waves[3];                                    // dir.x, dir.y, amplitude, wavelength

uniform vec3 shallow : source_color = vec3(0.38, 0.90, 0.86);
uniform vec3 mid : source_color = vec3(0.10, 0.68, 0.80);
uniform vec3 deep : source_color = vec3(0.06, 0.40, 0.70);
uniform vec3 foam : source_color = vec3(1.0, 0.99, 0.95);

varying vec3 wpos;
varying float wave_h;

float ground_at(vec2 xz) {
	vec2 uv = (xz - ground_rect.xy) / ground_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return -8.0;
	return texture(ground_height, uv).r;
}

vec3 wave(vec2 xz) {
	// returns (height, dh/dx, dh/dz); calm beyond the detailed patch (see ocean.gd)
	vec3 r = vec3(0.0);
	float fade = 1.0 - smoothstep(170.0, 195.0, max(abs(xz.x), abs(xz.y)));
	for (int i = 0; i < 3; i++) {
		vec2 d = normalize(waves[i].xy);
		float k = 6.2831853 / waves[i].w;
		float w = sqrt(9.8 * k);
		float ph = k * dot(d, xz) - w * t + float(i) * 1.7;
		r.x += waves[i].z * sin(ph) * fade;
		r.yz += waves[i].z * k * cos(ph) * d * fade;
	}
	return r;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wv = wave(wpos.xz);
	VERTEX.y += wv.x;
	wave_h = wv.x;
	NORMAL = normalize(vec3(-wv.y, 1.0, -wv.z));
	wpos.y += wv.x;
}

void fragment() {
	vec2 xz = wpos.xz;
	float ground = ground_at(xz);
	float depth = max(wpos.y - ground, 0.0);
	float n = fbm(xz * 0.35 + vec2(t * 0.05, t * 0.03));
	float n2 = vnoise(xz * 1.4 - vec2(t * 0.2, t * 0.12));

	vec3 col = mix(shallow, mid, smoothstep(0.1, 1.8, depth + (n - 0.5) * 0.4));
	col = mix(col, deep, smoothstep(2.0, 7.0, depth));

	// Shoreline foam: a solid lip plus bands that roll in towards the sand.
	float lip = smoothstep(0.22, 0.05, depth + (n2 - 0.5) * 0.12);
	float phase = fract(t * 0.18 + n * 0.25);
	float band_d = mix(1.1, 0.12, phase);
	float band = smoothstep(0.07, 0.0, abs(depth - band_d)) * (1.0 - phase) * step(depth, 1.3);
	band *= smoothstep(0.35, 0.6, n2 + 0.2);
	// Crests out at sea get a few whitecaps.
	float caps = smoothstep(0.17, 0.22, wave_h + (n2 - 0.5) * 0.12) * smoothstep(3.0, 6.0, depth) * 0.5;
	float f = clamp(max(lip, band) + caps, 0.0, 1.0);

	// Sun glints: sparse twinkling cells.
	vec2 gc = floor(xz * 2.2);
	float g = hash12(gc + floor(t * 1.5));
	float glint = step(0.985, g) * smoothstep(0.35, 0.0, length(fract(xz * 2.2) - 0.5));

	ALBEDO = mix(col, foam, f);
	EMISSION = vec3(glint) * 0.6;
	ROUGHNESS = mix(0.06, 0.6, f);
	SPECULAR = 0.55;
	ALPHA = clamp(mix(0.45, 0.97, smoothstep(0.0, 2.8, depth)) + f, 0.0, 1.0);
}

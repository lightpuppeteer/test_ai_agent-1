shader_type spatial;
// Stylised toon sea: you see the sand through clear shallows (refracted and
// absorbed, Beer's law), then crisp bands of turquoise, teal and blue, a
// drifting web of light ripples, toon foam where the waves lap the beach,
// and sun glints. (Toon bands after "Stylized Toon Water" by Thundergecko8,
// absorption after "Absorption-based stylized water", godotshaders.com.)
// The wave function is mirrored on the CPU by ocean.gd (buoyancy).
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/cozy_common.gdshaderinc"

#include "res://shaders/noise.gdshaderinc"

uniform float t = 0.0;                                    // synced simulation time
uniform sampler2D ground_height : filter_linear, repeat_disable;
uniform vec4 ground_rect;                                 // x0, z0, size, size
uniform vec4 waves[3];                                    // dir.x, dir.y, amplitude, wavelength

uniform vec3 shallow : source_color = vec3(0.38, 0.90, 0.86);
uniform vec3 mid : source_color = vec3(0.10, 0.68, 0.80);
uniform vec3 deep : source_color = vec3(0.06, 0.40, 0.70);
uniform vec3 foam : source_color = vec3(1.0, 0.99, 0.95);
uniform vec3 absorb_tint : source_color = vec3(0.62, 0.95, 0.9);
uniform float beers_law = 0.9;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;
varying float wave_h;

vec2 cell_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi edge: a soft web of light ripples.
float ripple_web(vec2 p, float time) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = 0.5 + 0.4 * sin(time + 6.2831 * cell_hash(i + g));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

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
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec2 xz = wpos.xz;
	float ground = ground_at(xz);
	float depth = max(wpos.y - ground, 0.0);
	float n = fbm(xz * 0.35 + vec2(t * 0.05, t * 0.03));
	float n2 = vnoise(xz * 1.4 - vec2(t * 0.2, t * 0.12));
	float dn = depth + (n - 0.5) * 0.5;

	// Crisp toon bands (slightly soft edges) from shallow to deep.
	vec3 col = shallow;
	col = mix(col, mid, smoothstep(0.55, 0.7, dn));
	col = mix(col, mix(mid, deep, 0.45), smoothstep(2.1, 2.3, dn));
	col = mix(col, deep, smoothstep(5.0, 5.4, dn));

	// Light ripples drifting over the shallows and the middle band.
	float web = 1.0 - smoothstep(0.0, 0.07, ripple_web(xz * 0.55 + vec2(t * 0.04, 0.0), t * 0.7));
	web *= (1.0 - smoothstep(1.8, 4.0, depth)) * 0.45;

	// Shoreline foam: a solid lip plus bands that roll in towards the sand.
	float lip = smoothstep(0.2, 0.12, depth + (n2 - 0.5) * 0.14);
	float phase = fract(t * 0.18 + n * 0.25);
	float band_d = mix(1.1, 0.12, phase);
	float band = smoothstep(0.06, 0.03, abs(depth - band_d)) * step(0.15, 1.0 - phase) * step(depth, 1.3);
	band *= step(0.45, n2 + 0.2);
	// Crests out at sea get a few toon whitecaps.
	float caps = step(0.19, wave_h + (n2 - 0.5) * 0.12) * smoothstep(3.0, 6.0, depth) * 0.6;
	float f = clamp(max(lip, band) + caps, 0.0, 1.0);

	// See through the shallows: refracted sand, tinted and absorbed with depth.
	float absorb = 1.0 - exp(-depth * beers_law);
	vec2 ofs = (vec2(n2, n) - 0.5) * 0.025 * smoothstep(0.0, 0.8, depth);
	vec3 under = textureLod(screen_tex, SCREEN_UV + ofs, 0.0).rgb * absorb_tint;
	float see = (1.0 - smoothstep(0.0, 0.9, absorb)) * (1.0 - f);

	// Sun glints: sparse twinkling cells.
	vec2 gc = floor(xz * 2.2);
	float g = hash12(gc + floor(t * 1.5));
	float glint = step(0.985, g) * smoothstep(0.35, 0.0, length(fract(xz * 2.2) - 0.5));

	vec3 water = mix(col, vec3(1.0), web);
	ALBEDO = mix(water * (1.0 - see), foam, f);
	EMISSION = under * see + vec3(glint) * 0.6 + vec3(web) * 0.05;
	ROUGHNESS = mix(0.08, 0.6, f);
	SPECULAR = 0.5;
	ALPHA = 1.0;
}

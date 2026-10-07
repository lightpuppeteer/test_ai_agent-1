shader_type spatial;
// Painted island ground: lush grass with soft patches, warm sand that darkens
// near the water, dirt footpaths, stone paving, cobbled road and rocky cliffs.
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D splat : filter_linear, repeat_disable;   // r path, g paving, b road, a soil
uniform vec4 splat_rect;                                    // x0, z0, width, depth

uniform vec3 grass_a : source_color = vec3(0.33, 0.62, 0.25);
uniform vec3 grass_b : source_color = vec3(0.45, 0.72, 0.29);
uniform vec3 grass_c : source_color = vec3(0.60, 0.74, 0.32);
uniform vec3 sand_dry : source_color = vec3(0.93, 0.83, 0.62);
uniform vec3 sand_wet : source_color = vec3(0.78, 0.66, 0.47);
uniform vec3 dirt : source_color = vec3(0.80, 0.64, 0.44);
uniform vec3 paving : source_color = vec3(0.80, 0.74, 0.66);
uniform vec3 road_col : source_color = vec3(0.78, 0.70, 0.62);
uniform vec3 rock : source_color = vec3(0.60, 0.50, 0.42);
uniform vec3 soil : source_color = vec3(0.47, 0.33, 0.24);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Staggered tile pattern: returns (grout mask, per-tile random).
vec2 tiles(vec2 p, vec2 size, float grout) {
	vec2 q = p / size;
	q.x += step(1.0, mod(floor(q.y), 2.0)) * 0.5;
	vec2 id = floor(q);
	vec2 f = fract(q);
	vec2 e = min(f, 1.0 - f) * size;
	float g = smoothstep(grout, grout + 0.03, min(e.x, e.y));
	return vec2(g, hash12(id));
}

void fragment() {
	vec2 xz = wpos.xz;
	float h = wpos.y;
	vec2 suv = (xz - splat_rect.xy) / splat_rect.zw;
	vec4 sp = texture(splat, suv);
	if (suv.x < 0.0 || suv.y < 0.0 || suv.x > 1.0 || suv.y > 1.0) sp = vec4(0.0);

	float n1 = fbm(xz * 0.06);
	float n2 = vnoise(xz * 0.45);
	float n3 = vnoise(xz * 2.3);

	// --- grass: broad patches + small clumps + tiny speckles
	vec3 col = mix(grass_a, grass_b, smoothstep(0.35, 0.65, n1));
	col = mix(col, grass_c, smoothstep(0.62, 0.8, n2) * 0.45);
	col *= 0.93 + 0.1 * n3;
	// little darker "grass marks" like hand-painted tufts
	vec2 cell = floor(xz * 1.6);
	vec2 cf = fract(xz * 1.6) - 0.5;
	float r = hash12(cell);
	vec2 off = vec2(hash12(cell + 7.1), hash12(cell + 3.7)) - 0.5;
	float mark = smoothstep(0.12, 0.05, length((cf - off * 0.5) * vec2(1.0, 2.2))) * step(0.72, r);
	col = mix(col, grass_a * 0.78, mark * 0.6);

	// --- sand (by height), wet near the waterline
	float sand_amt = 1.0 - smoothstep(1.22, 1.55, h + (n2 - 0.5) * 0.25);
	vec3 sand = mix(sand_wet, sand_dry, smoothstep(0.05, 0.55, h + (n3 - 0.5) * 0.08));
	sand *= 0.95 + 0.07 * n3 + 0.05 * hash12(floor(xz * 9.0));
	col = mix(col, sand, sand_amt);

	// --- dirt paths with organic edges
	float path_amt = smoothstep(0.38, 0.62, sp.r + (n2 - 0.5) * 0.35);
	vec3 dirt_c = dirt * (0.9 + 0.15 * n3);
	float pebble = step(0.86, hash12(floor(xz * 5.0))) * 0.12;
	col = mix(col, dirt_c * (1.0 + pebble), path_amt);

	// --- soil (flower beds)
	float soil_amt = smoothstep(0.4, 0.6, sp.a + (n3 - 0.5) * 0.2);
	col = mix(col, soil * (0.9 + 0.2 * n3), soil_amt);

	// --- paving: warm stone slabs
	vec2 t1 = tiles(xz, vec2(1.1, 0.75), 0.03);
	vec3 pave = paving * (0.9 + 0.14 * t1.y) * mix(0.72, 1.0, t1.x);
	float pave_amt = smoothstep(0.4, 0.6, sp.g);
	col = mix(col, pave, pave_amt);

	// --- road: rounded cobbles
	vec2 t2 = tiles(xz, vec2(0.55, 0.45), 0.025);
	vec3 cob = road_col * (0.86 + 0.2 * t2.y) * mix(0.68, 1.0, t2.x);
	float road_amt = smoothstep(0.4, 0.6, sp.b);
	col = mix(col, cob, road_amt);

	// --- cliffs: steep faces become layered rock
	float slope = 1.0 - wnrm.y;
	float cliff = smoothstep(0.32, 0.5, slope + (n2 - 0.5) * 0.12);
	// Chunky layered rock: crisp horizontal bands broken by vertical cracks.
	float band = fract(h * 1.6 + vnoise(xz * 0.35) * 0.6);
	float strata = mix(0.8, 1.0, smoothstep(0.08, 0.14, band)) * mix(1.0, 0.9, step(0.55, band));
	float crack = smoothstep(0.455, 0.485, abs(fract(dot(xz, vec2(0.7, 0.7)) * 0.9 + vnoise(vec2(h * 0.8, xz.x * 0.2)) * 0.8) - 0.5));
	vec3 rock_c = rock * strata * (0.94 + 0.08 * n3) * (1.0 - crack * 0.25);
	col = mix(col, rock_c, cliff);

	ALBEDO = col;
	float wet = sand_amt * (1.0 - smoothstep(0.05, 0.45, h));
	ROUGHNESS = mix(0.92, 0.45, wet) - pave_amt * 0.1;
	SPECULAR = 0.25 + wet * 0.25;
}

shader_type spatial;
// Indoor floors: warm wooden planks, or checker tiles.
render_mode diffuse_burley;
#include "res://shaders/cozy_common.gdshaderinc"

#include "res://shaders/noise.gdshaderinc"

uniform vec3 base : source_color = vec3(0.78, 0.6, 0.42);
uniform bool tiles = false;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 col;
	if (tiles) {
		vec2 c = floor(p / 0.8);
		float chk = mod(c.x + c.y, 2.0);
		vec2 f = fract(p / 0.8);
		float grout = step(0.03, min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)));
		col = mix(base * 0.82, base * 1.08, chk) * mix(0.75, 1.0, grout);
	} else {
		vec2 q = vec2(p.x / 0.22, p.y / 1.6);
		q.y += hash12(vec2(floor(q.x), 3.0)) * 3.0;
		vec2 id = floor(q);
		vec2 f = fract(q);
		float seam = step(0.04, f.x) * step(0.015, f.y);
		float tone = 0.88 + 0.16 * hash12(id);
		float grain = 0.95 + 0.05 * sin(p.y * 40.0 + vnoise(p * 3.0) * 6.0);
		col = base * tone * grain * mix(0.7, 1.0, seam);
	}
	ALBEDO = col;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
}

void light() {
	cozy_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, ROUGHNESS, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}

shader_type spatial;
// Volcano rock: dark banded basalt that lightens towards a sandy foot,
// with glowing cracks near the top.
render_mode diffuse_burley;
#include "res://shaders/cozy_common.gdshaderinc"

#include "res://shaders/noise.gdshaderinc"

varying vec3 lpos;
varying vec3 wpos;

void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
}

void fragment() {
	float h = clamp((lpos.y + 23.0) / 46.0, 0.0, 1.0);
	float band = 0.85 + 0.15 * step(0.5, fract(wpos.y * 0.35 + vnoise(wpos.xz * 0.08) * 1.5));
	vec3 rock = mix(vec3(0.5, 0.3, 0.22), vec3(0.26, 0.16, 0.14), smoothstep(0.1, 0.7, h)) * band;
	rock *= 0.9 + 0.15 * vnoise(wpos.xz * 0.4 + wpos.y * 0.2);
	float crack = smoothstep(0.82, 0.88, vnoise(vec2(atan(lpos.z, lpos.x) * 6.0, wpos.y * 0.3))) * smoothstep(0.6, 0.95, h);
	ALBEDO = mix(rock, vec3(1.0, 0.4, 0.1), crack);
	EMISSION = vec3(1.0, 0.35, 0.05) * crack * 2.0;
	ROUGHNESS = 0.95;
}

void light() {
	cozy_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, ROUGHNESS, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}

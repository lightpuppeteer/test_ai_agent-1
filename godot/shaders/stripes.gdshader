shader_type spatial;
// Striped fabric for beach towels, parasols and picnic blankets.
render_mode cull_disabled, diffuse_burley;
#include "res://shaders/cozy_common.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.98, 0.45, 0.45);
uniform vec3 color_b : source_color = vec3(1.0, 0.96, 0.90);
uniform float stripes = 6.0;
uniform bool radial = false;     // parasol: stripes around the axis
uniform bool checker = false;    // picnic blanket
uniform float fringe = 0.0;      // towel ends get a thin band of color_b

void vertex() {
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
}

void fragment() {
	float s;
	if (radial) {
		vec2 p = UV - 0.5;
		s = step(0.5, fract(atan(p.y, p.x) / 6.2831853 * stripes));
	} else if (checker) {
		vec2 c = floor(UV * stripes);
		s = mod(c.x + c.y, 2.0);
	} else {
		s = step(0.5, fract(UV.x * stripes));
	}
	vec3 col = mix(color_a, color_b, s);
	if (fringe > 0.0) {
		float e = min(UV.y, 1.0 - UV.y);
		col = mix(col, color_b, step(e, fringe) * 0.85);
	}
	// soft woven texture
	float weave = sin(UV.x * 900.0) * sin(UV.y * 900.0) * 0.03;
	ALBEDO = col * (0.97 + weave);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}

void light() {
	cozy_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, ROUGHNESS, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}

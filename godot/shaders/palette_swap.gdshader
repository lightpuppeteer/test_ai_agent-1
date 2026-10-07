shader_type spatial;
// Recolours palette-textured models on the GPU: texels whose hue/saturation
// match a source colour take the hue (and relative saturation/value) of a target.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec3 from_a : source_color;
uniform vec3 to_a : source_color;
uniform vec3 from_b : source_color;
uniform vec3 to_b : source_color;
uniform bool use_b = false;
uniform float roughness = 0.8;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float matches(vec3 c, vec3 from) {
	vec3 h = rgb2hsv(c);
	vec3 hf = rgb2hsv(from);
	float dh = abs(h.x - hf.x);
	dh = min(dh, 1.0 - dh);
	return step(dh, 0.045) * step(abs(h.y - hf.y), 0.16);
}

vec3 swapped(vec3 c, vec3 from, vec3 to) {
	vec3 h = rgb2hsv(c);
	vec3 hf = rgb2hsv(from);
	vec3 ht = rgb2hsv(to);
	vec3 n = vec3(ht.x, clamp(h.y * ht.y / max(hf.y, 0.01), 0.0, 1.0), clamp(h.z * ht.z / max(hf.z, 0.01), 0.0, 1.0));
	return hsv2rgb(n);
}

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
}

void fragment() {
	// Both swaps test the ORIGINAL texel, so a recoloured texel can't be swapped twice.
	vec3 o = texture(albedo_tex, UV).rgb;
	vec3 c = mix(o, swapped(o, from_a, to_a), matches(o, from_a));
	if (use_b) {
		float mb = matches(o, from_b) * (1.0 - matches(o, from_a));
		c = mix(c, swapped(o, from_b, to_b), mb);
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}

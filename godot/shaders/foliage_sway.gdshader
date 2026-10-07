shader_type spatial;
// Gentle wind sway for leaves, palms, flowers and grass tufts.
// Displacement grows with height above the model base, so trunks stay planted.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform bool use_tex = false;
uniform float strength = 1.0;       // overall sway amount (model-local units ~ metres / kit scale)
uniform float height = 1.0;         // model height (local units)
uniform float base = 0.0;           // model base (local units)
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float translucency : hint_range(0.0, 1.0) = 0.25;

uniform float green_shift : hint_range(0.0, 1.0) = 1.0;   // pull teal greens towards warm leaf green

varying float v_weight;

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

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp((VERTEX.y - base) / height, 0.0, 1.0);
	float w = h * h;
	v_weight = h;
	float t = TIME;
	float phase = dot(wpos.xz, vec2(0.13, 0.17));
	float gust = 0.6 + 0.4 * sin(t * 0.35 + wpos.x * 0.02);
	float sway = (sin(t * 1.3 + phase) * 0.7 + sin(t * 2.7 + phase * 2.3) * 0.3) * gust;
	float flutter = sin(t * 7.0 + dot(VERTEX, vec3(9.1, 7.3, 8.7))) * 0.15;
	vec2 dir = normalize(wind_dir);
	// Work in local space: convert world wind direction to the model's frame.
	vec3 local_dir = normalize((inverse(MODEL_MATRIX) * vec4(dir.x, 0.0, dir.y, 0.0)).xyz);
	VERTEX += local_dir * (sway + flutter) * strength * 0.04 * w * height;
	VERTEX.y -= abs(sway) * strength * 0.01 * w * height;
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(albedo_tex, UV);
	}
	if (green_shift > 0.0) {
		vec3 hsv = rgb2hsv(c.rgb);
		float w = smoothstep(0.30, 0.37, hsv.x) * smoothstep(0.60, 0.52, hsv.x) * green_shift;
		hsv.x = mix(hsv.x, 0.27, w);
		hsv.z *= mix(1.0, 0.9, w);
		c.rgb = hsv2rgb(hsv);
	}
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	// Fake subsurface: leaves glow a little when back-lit.
	BACKLIGHT = c.rgb * translucency * v_weight;
}

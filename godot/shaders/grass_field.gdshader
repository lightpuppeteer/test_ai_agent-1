// Short, soft Animal Crossing–style grass: little tufts of rounded blades that
// sway in the wind and bend away from whoever walks through them.
// UV.y = 0 at the root, 1 at the tip. INSTANCE_CUSTOM.r = colour variation.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://shaders/cozy_common.gdshaderinc"

global uniform vec3 player_pos;
global uniform vec3 partner_pos;

uniform vec3 root_col : source_color = vec3(0.30, 0.56, 0.24);
uniform vec3 tip_col : source_color = vec3(0.56, 0.80, 0.34);
uniform vec3 dry_tip : source_color = vec3(0.72, 0.80, 0.36);
uniform float wind_strength = 0.11;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float push_radius = 0.9;
uniform float push_strength = 0.32;

varying float v_h;
varying float v_var;

vec3 push_from(vec3 who, vec3 wp, float h) {
	vec2 d = wp.xz - who.xz;
	float dist = length(d);
	float near_y = 1.0 - smoothstep(0.6, 1.4, abs(wp.y - who.y));
	float f = (1.0 - smoothstep(0.15, push_radius, dist)) * near_y;
	vec2 dir = dist > 0.001 ? d / dist : vec2(0.0);
	return vec3(dir.x, -0.55, dir.y) * f * push_strength * h;
}

void vertex() {
	float h = UV.y;
	v_h = h;
	v_var = INSTANCE_CUSTOM.r;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = MODEL_MATRIX[3].xyz;
	float t = TIME;
	float phase = dot(root.xz, vec2(0.21, 0.17));
	float gust = 0.55 + 0.45 * sin(t * 0.4 + root.x * 0.03 + root.z * 0.02);
	float sway = (sin(t * 1.7 + phase) * 0.7 + sin(t * 3.1 + phase * 1.9) * 0.3) * gust;
	vec2 wd = normalize(wind_dir);
	vec3 disp = vec3(wd.x, 0.0, wd.y) * sway * wind_strength * h * h;
	disp += push_from(player_pos, root, h * h);
	disp += push_from(partner_pos, root, h * h);
	// World-space bend back into model space (rotation + uniform scale).
	mat3 m = mat3(MODEL_MATRIX);
	float s2 = dot(m[0], m[0]);
	VERTEX += (transpose(m) * disp) / max(s2, 1e-5);
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
	// Light the tufts like the ground they grow from (soft, no harsh blade edges).
	NORMAL = normalize(transpose(m) * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec3 tip = mix(tip_col, dry_tip, smoothstep(0.65, 1.0, v_var) * 0.6);
	vec3 base = root_col * (0.92 + v_var * 0.16);
	vec3 c = mix(base, tip, smoothstep(0.0, 1.0, v_h));
	ALBEDO = c;
	ROUGHNESS = 0.95;
	BACKLIGHT = c * 0.25 * v_h;
	AO = mix(0.65, 1.0, v_h);
	AO_LIGHT_AFFECT = 0.5;
}

void light() {
	cozy_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, 0.95, DIFFUSE_LIGHT, SPECULAR_LIGHT, LIGHT_IS_DIRECTIONAL);
}

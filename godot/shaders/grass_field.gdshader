// A thick, short Animal Crossing–style lawn. Each instance is a 1 m turf of
// single-triangle blades (scripts/world/grass_field.gd). Per blade, the vertex
// shader:
//  - drops the root onto the real ground height (terrain height texture),
//  - hides blades that land on paths, paving, road, soil or sand (splat map),
//  - shrinks blades into the ground towards the edge of the draw distance,
//  - sways them in the wind and bends them away from Tatiana and Marco.
// UV.y = 0 at the root, 1 at the tip; UV.x = per-blade random; UV2 = root (x, z).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://shaders/cozy_common.gdshaderinc"

global uniform vec3 player_pos;
global uniform vec3 partner_pos;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec3 height_info;                  // terrain size (m), vertices per side
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec4 splat_rect;                   // x0, z0, width, depth
uniform vec2 lod_in = vec2(-2.0, -1.0);    // this detail level grows in over [x, y] metres
uniform vec2 lod_out = vec2(24.0, 30.0);   // … and shrinks out over [x, y]

uniform vec3 root_col : source_color = vec3(0.27, 0.53, 0.22);
uniform vec3 tip_col : source_color = vec3(0.55, 0.80, 0.33);
uniform vec3 dry_tip : source_color = vec3(0.70, 0.80, 0.36);
uniform float wind_strength = 0.1;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float push_radius = 0.9;
uniform float push_strength = 0.3;

varying float v_h;
varying float v_var;

float ground_at(vec2 xz) {
	float size = height_info.x;
	float n = height_info.y;
	vec2 uv = ((xz + vec2(size * 0.5)) / (size / (n - 1.0)) + 0.5) / n;
	return textureLod(height_tex, uv, 0.0).r;
}

vec3 push_from(vec3 who, vec3 wp) {
	vec2 d = wp.xz - who.xz;
	float dist = length(d);
	float near_y = 1.0 - smoothstep(0.6, 1.4, abs(wp.y - who.y));
	float f = (1.0 - smoothstep(0.15, push_radius, dist)) * near_y;
	vec2 dir = dist > 0.001 ? d / dist : vec2(0.0);
	return vec3(dir.x, -0.55, dir.y) * f * push_strength;
}

void vertex() {
	float h = UV.y;
	v_h = h;
	v_var = UV.x;
	mat3 m = mat3(MODEL_MATRIX);
	float s = length(m[0]);
	vec3 root_local = vec3(UV2.x, 0.0, UV2.y);
	vec3 root = (MODEL_MATRIX * vec4(root_local, 1.0)).xyz;
	// Lawn or not, from the painted ground under the root.
	vec4 sp = textureLod(splat, (root.xz - splat_rect.xy) / splat_rect.zw, 0.0);
	float bare = max(max(sp.r, sp.g), max(sp.b, sp.a));
	float gy = ground_at(root.xz);
	float keep = (1.0 - smoothstep(0.25, 0.5, bare)) * smoothstep(1.2, 1.45, gy);
	// Hand over smoothly between detail levels (and fade out at the far edge).
	float cam_d = length(root - INV_VIEW_MATRIX[3].xyz);
	keep *= smoothstep(lod_in.x, lod_in.y, cam_d) * (1.0 - smoothstep(lod_out.x, lod_out.y, cam_d));
	// Blade shape relative to its root, scaled by keep; root on the ground.
	vec3 rel = (VERTEX - root_local) * keep;
	VERTEX = root_local + rel;
	VERTEX.y += (gy - MODEL_MATRIX[3].y) / max(s, 1e-4);
	// Wind and push, in world space, converted back to model space.
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float phase = dot(root.xz, vec2(0.21, 0.17));
	float gust = 0.55 + 0.45 * sin(t * 0.4 + root.x * 0.03 + root.z * 0.02);
	float sway = (sin(t * 1.7 + phase) * 0.7 + sin(t * 3.1 + phase * 1.9) * 0.3) * gust;
	vec2 wd = normalize(wind_dir);
	vec3 disp = vec3(wd.x, 0.0, wd.y) * sway * wind_strength;
	disp += push_from(player_pos, root);
	disp += push_from(partner_pos, root);
	disp *= h * h * keep;
	VERTEX += (transpose(m) * disp) / max(s * s, 1e-5);
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
	// Lit like the ground it grows from (soft, no harsh blade edges).
	NORMAL = normalize(transpose(m) * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec3 tip = mix(tip_col, dry_tip, smoothstep(0.7, 1.0, v_var) * 0.6);
	vec3 base = root_col * (0.9 + v_var * 0.2);
	vec3 c = mix(base, tip, smoothstep(0.0, 1.0, v_h));
	ALBEDO = c;
	ROUGHNESS = 0.95;
	BACKLIGHT = c * 0.25 * v_h;
	AO = mix(0.7, 1.0, v_h);
	AO_LIGHT_AFFECT = 0.5;
}

void light() {
	cozy_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, 0.95, DIFFUSE_LIGHT, SPECULAR_LIGHT, LIGHT_IS_DIRECTIONAL);
}

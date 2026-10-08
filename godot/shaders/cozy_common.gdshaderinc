// Shared "cozy" look: the rolling-log world curve and soft toon lighting.
// Globals are set every frame by Game (camera position / forward).

global uniform float curve_amount;
global uniform vec3 curve_origin;
global uniform vec3 curve_dir;
// Cool, soft colour that sunlit-side shadows fade to (Animal Crossing shadows are
// lavender-blue, never grey). rgb = tint, a = strength. Set per time of day.
global uniform vec4 shadow_tint;

// How far a world point sinks: the world rolls away from the camera like a log,
// mostly along the view direction and a little to the sides.
float curve_drop(vec3 w) {
	vec2 d = w.xz - curve_origin.xz;
	vec2 f = normalize(curve_dir.xz + vec2(1e-5, 0.0));
	float along = dot(d, f);
	float side = dot(d, vec2(-f.y, f.x));
	return (along * along + side * side * 0.3) * curve_amount;
}

// Model-space vertex bent by the world curve. Model matrices here are rotation
// + (near) uniform scale, so the inverse is the transpose over scale².
vec3 curve_local(vec3 vertex, mat4 model) {
	vec3 w = (model * vec4(vertex, 1.0)).xyz;
	float d = curve_drop(w);
	vec3 up_local = vec3(model[0][1], model[1][1], model[2][1]) / max(dot(model[0].xyz, model[0].xyz), 1e-6);
	return vertex - up_local * d;
}

// Soft cel lighting: a smooth terminator, sky-filled shadows (ambient does the
// rest), a little rim light and a gentle highlight.
void cozy_light(vec3 normal, vec3 light, vec3 view, vec3 light_color, float attenuation, float rough,
		inout vec3 diffuse, inout vec3 specular, bool directional) {
	float ndl = dot(normal, light);
	float band = smoothstep(-0.1, 0.35, ndl);
	// Soften the shadow edge a touch (shadow maps are filtered; this widens the ramp).
	float lit = directional ? smoothstep(0.0, 0.85, attenuation) : attenuation;
	diffuse += light_color * band * lit * 0.3183;
	if (directional) {
		// Cast shadows and the turned-away side get a cool, gentle fill.
		float shade = (1.0 - lit) * smoothstep(-0.6, 0.35, ndl) + (1.0 - band) * 0.35;
		diffuse += shadow_tint.rgb * shadow_tint.a * shade * 0.3183;
	}
	float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0) * smoothstep(-0.2, 0.6, ndl);
	diffuse += light_color * rim * 0.14 * attenuation * 0.3183;
	vec3 h = normalize(light + view);
	float s = pow(clamp(dot(normal, h), 0.0, 1.0), mix(90.0, 10.0, rough));
	specular += light_color * smoothstep(0.45, 0.9, s) * (1.0 - rough) * 0.22 * attenuation;
}

// Dissolve anything right in front of the lens (e.g. when the camera slips
// into a tree canopy) with a soft dither instead of showing its inside.
bool near_cut_at(vec3 view_pos, vec2 frag, float far_d) {
	float d = length(view_pos);
	if (d > far_d) return false;
	float n = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	return n > smoothstep(far_d * 0.375, far_d, d);
}

bool near_cut(vec3 view_pos, vec2 frag) {
	return near_cut_at(view_pos, frag, 2.4);
}

// Shared "cozy" look: the rolling-log world curve and soft toon lighting.
// Globals are set every frame by Game (camera position / forward).

global uniform float curve_amount;
global uniform vec3 curve_origin;
global uniform vec3 curve_dir;

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
		inout vec3 diffuse, inout vec3 specular) {
	float ndl = dot(normal, light);
	float band = smoothstep(-0.1, 0.35, ndl);
	diffuse += light_color * band * attenuation * 0.3183;
	float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0) * smoothstep(-0.2, 0.6, ndl);
	diffuse += light_color * rim * 0.14 * attenuation * 0.3183;
	vec3 h = normalize(light + view);
	float s = pow(clamp(dot(normal, h), 0.0, 1.0), mix(90.0, 10.0, rough));
	specular += light_color * smoothstep(0.45, 0.9, s) * (1.0 - rough) * 0.22 * attenuation;
}

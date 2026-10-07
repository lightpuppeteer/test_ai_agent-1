shader_type sky;
// Soft storybook sky: a clean blue gradient, a warm horizon, a gentle sun halo
// and puffy drifting clouds.

#include "res://shaders/noise.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.33, 0.60, 0.93);
uniform vec3 horizon : source_color = vec3(0.80, 0.91, 0.99);
uniform vec3 below : source_color = vec3(0.55, 0.78, 0.88);
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.74, 0.80, 0.92);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform float sun_halo = 0.35;
uniform float time_scale = 1.0;

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(y, 0.0, 1.0), 0.55));
	col = mix(col, below, smoothstep(0.0, -0.12, y));

	// Sun: a soft disc and a wide warm glow.
	vec3 sdir = LIGHT0_DIRECTION;
	float sd = max(dot(d, sdir), 0.0);
	vec3 scol = LIGHT0_COLOR;
	col += scol * (pow(sd, 8.0) * sun_halo + pow(sd, 120.0) * 0.6);
	col += scol * smoothstep(0.9993, 0.9997, sd) * 2.0;

	// Clouds on a curved dome.
	if (y > 0.0) {
		vec2 p = d.xz / (y + 0.12) * 1.4 + vec2(TIME * 0.006, TIME * 0.002) * time_scale;
		float c = fbm(p * 1.1);
		c += 0.35 * fbm(p * 3.1 + 4.0);
		float cover = smoothstep(1.05 - cloud_cover, 1.25 - cloud_cover * 0.8, c);
		cover *= smoothstep(0.0, 0.18, y);
		float shade = smoothstep(0.2, 1.0, fbm(p * 2.0 + 9.0));
		vec3 cc = mix(cloud_lit, cloud_shade, shade * 0.7);
		cc += scol * pow(sd, 6.0) * 0.4;
		col = mix(col, cc, cover * 0.95);
	}
	COLOR = col;
}

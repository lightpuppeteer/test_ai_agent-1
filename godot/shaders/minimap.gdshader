shader_type canvas_item;
// Round window onto the island map texture, centred on the player.

uniform vec2 center = vec2(0.5);
uniform float radius = 0.25;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d);
	vec2 uv = center + d * 2.0 * radius;
	vec4 c = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) c = vec4(0.3, 0.6, 0.85, 1.0);
	float a = smoothstep(0.5, 0.49, r);
	COLOR = vec4(c.rgb, a * 0.95);
}

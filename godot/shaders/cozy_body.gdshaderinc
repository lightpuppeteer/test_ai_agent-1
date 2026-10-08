// Body of the cozy material (StandardMaterial3D look-alike with the cozy light).
#include "res://shaders/cozy_common.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform bool vcol_srgb = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular_amt : hint_range(0.0, 1.0) = 0.4;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;
uniform float scissor = 0.5;
uniform bool near_fade = false;     // dissolve near the camera (tree canopies, characters)
uniform float near_fade_dist = 2.4; // fully solid beyond this distance

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	VERTEX = curve_local(VERTEX, MODEL_MATRIX);
}

void fragment() {
	if (near_fade && near_cut_at(VERTEX, FRAGCOORD.xy, near_fade_dist)) {
		discard;
	}
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(albedo_tex, UV);
	}
	if (use_vcol) {
		vec3 vc = COLOR.rgb;
		if (vcol_srgb) {
			vc = mix(pow((vc + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), vc * (1.0 / 12.92), lessThan(vc, vec3(0.04045)));
		}
		c.rgb *= vc;
		c.a *= COLOR.a;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular_amt;
	vec3 em = emission.rgb * emission_energy;
	if (use_emission_tex) {
		em *= texture(emission_tex, UV).rgb;
	}
	EMISSION = em;
#ifdef COZY_CUTOUT
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = scissor;
#endif
#ifdef COZY_ALPHA
	ALPHA = c.a;
#endif
}

void light() {
	cozy_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, roughness, DIFFUSE_LIGHT, SPECULAR_LIGHT, LIGHT_IS_DIRECTIONAL);
}

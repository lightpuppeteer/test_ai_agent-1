import * as THREE from 'three';

/**
 * Global ShaderChunk overrides, installed once before any material compiles.
 *
 * 1. Contact-hardening soft shadows (PCSS-style) for PCFShadowMap.
 *    r186 removed PCFSoftShadowMap (it now aliases PCF with a warning), and
 *    its PCF path samples a *comparison* sampler, so classic PCSS blocker
 *    search (which reads raw depth) is impossible. Instead we estimate the
 *    blocker→receiver distance with comparison taps at increasing depth
 *    offsets: taps that stay occluded even when the receiver is moved
 *    towards the light reveal distant blockers. The penumbra radius scales
 *    with that distance, so shadows are crisp at contact and soften with
 *    distance — the "ray-traced" look — using only hardware PCF taps.
 *
 * 2. Height fog. Standard FogExp2 is kept for the horizon; on top of it an
 *    analytic exponential height-fog integral along the view ray makes low
 *    altitudes (sea surface, beach, low streets) accumulate thicker haze than
 *    high ground, with forward in-scattering around the sun. Materials opt in
 *    with `defines.STY_HEIGHT_FOG` and the shared `heightFogUniforms`.
 */
export const heightFogUniforms = {
  uHFogDensity: { value: 0.0045 }, // extinction at the base height (1/m)
  uHFogFalloff: { value: 0.09 }, // 1/m — density halves every ln2/falloff metres
  uHFogBase: { value: 0.0 }, // world Y of the base (sea level)
  uHFogColor: { value: new THREE.Color(0xf0d2ae) },
  uHFogSunDir: { value: new THREE.Vector3(0, 1, 0) },
  uHFogSunColor: { value: new THREE.Color(0xffd7a6) },
};

let installed = false;

/**
 * @param {object} [o]
 * @param {number} [o.shadowTaps] filter taps (search uses the same count)
 * @param {number} [o.shadowDepthRange] shadow camera far - near (m), to convert metres → depth units
 * @param {number} [o.shadowTexelWorld] world size of one shadow texel (m)
 * @param {number} [o.lightAngle] apparent light size (radians); bigger = softer far shadows
 */
export function installShaderPatches({
  shadowTaps = 12,
  shadowDepthRange = 219,
  shadowTexelWorld = 0.0186,
  lightAngle = 0.035,
} = {}) {
  if (installed) return;
  installed = true;
  patchSoftShadows({ shadowTaps, shadowDepthRange, shadowTexelWorld, lightAngle });
  patchHeightFog();
}

function f(v) {
  const s = Number(v).toFixed(6);
  return s.includes('.') ? s : `${s}.0`;
}

function patchSoftShadows({ shadowTaps, shadowDepthRange, shadowTexelWorld, lightAngle }) {
  const chunk = THREE.ShaderChunk.shadowmap_pars_fragment;
  const pattern =
    /shadow = \(\s*texture\( shadowMap, vec3\( shadowCoord\.xy \+ vogelDiskSample\( 0, 5, phi \)[\s\S]*?\) \* 0\.2;/;
  if (!pattern.test(chunk)) {
    console.warn('ShaderPatches: PCF block not found — soft shadow patch skipped (three.js version changed?)');
    return;
  }
  const metresToDepth = 1 / shadowDepthRange;
  // Penumbra (in texels) per metre of blocker distance.
  const texelsPerMetre = Math.tan(lightAngle) / shadowTexelWorld;
  const replacement = /* glsl */ `
				// --- Contact-hardening soft shadows (see lighting/ShaderPatches.js) ---
				const int STY_TAPS = ${shadowTaps};
				// 1) Blocker distance estimate: fraction of taps still occluded when the
				//    receiver is pulled towards the light by increasing amounts.
				float searchRadius = shadowRadius * 3.0 * texelSize.x;
				float blockerMetres = 0.0;
				const float STY_STEPS[4] = float[4](0.15, 0.6, 1.5, 3.5);
				float prevStep = 0.0;
				for (int s = 0; s < 4; s++) {
					float dz = STY_STEPS[s] * ${f(metresToDepth)};
					float occ = 0.0;
					for (int i = 0; i < 3; i++) {
						vec2 o = vogelDiskSample(i + s * 3, 12, phi) * searchRadius;
						occ += 1.0 - texture(shadowMap, vec3(shadowCoord.xy + o, shadowCoord.z - dz));
					}
					blockerMetres += (occ / 3.0) * (STY_STEPS[s] - prevStep);
					prevStep = STY_STEPS[s];
				}
				// 2) Penumbra radius in texels: tight at contact, wider with distance.
				float penumbra = clamp(blockerMetres * ${f(texelsPerMetre)}, 0.75, shadowRadius * 2.5);
				float filterRadius = penumbra * texelSize.x;
				// 3) Rotated Vogel-disk PCF.
				shadow = 0.0;
				for (int i = 0; i < STY_TAPS; i++) {
					shadow += texture(shadowMap, vec3(shadowCoord.xy + vogelDiskSample(i, STY_TAPS, phi) * filterRadius, shadowCoord.z));
				}
				shadow /= float(STY_TAPS);`;
  THREE.ShaderChunk.shadowmap_pars_fragment = chunk.replace(pattern, replacement);
}

function patchHeightFog() {
  const C = THREE.ShaderChunk;
  C.fog_pars_vertex = /* glsl */ `
#ifdef USE_FOG
	varying float vFogDepth;
	#ifdef STY_HEIGHT_FOG
		varying vec3 vFogWorldPos;
	#endif
#endif
`;
  C.fog_vertex = /* glsl */ `
#ifdef USE_FOG
	vFogDepth = - mvPosition.z;
	#ifdef STY_HEIGHT_FOG
		// World position from the view-space position (rigid view matrix):
		// works in every shader that includes fog_vertex, instanced or not.
		vFogWorldPos = transpose( mat3( viewMatrix ) ) * ( mvPosition.xyz - viewMatrix[ 3 ].xyz );
	#endif
#endif
`;
  C.fog_pars_fragment = /* glsl */ `
#ifdef USE_FOG
	uniform vec3 fogColor;
	varying float vFogDepth;
	#ifdef FOG_EXP2
		uniform float fogDensity;
	#else
		uniform float fogNear;
		uniform float fogFar;
	#endif
	#ifdef STY_HEIGHT_FOG
		varying vec3 vFogWorldPos;
		uniform float uHFogDensity;
		uniform float uHFogFalloff;
		uniform float uHFogBase;
		uniform vec3 uHFogColor;
		uniform vec3 uHFogSunDir;
		uniform vec3 uHFogSunColor;
	#endif
#endif
`;
  C.fog_fragment = /* glsl */ `
#ifdef USE_FOG
	#ifdef FOG_EXP2
		float fogFactor = 1.0 - exp( - fogDensity * fogDensity * vFogDepth * vFogDepth );
	#else
		float fogFactor = smoothstep( fogNear, fogFar, vFogDepth );
	#endif
	vec3 styFogCol = fogColor;
	#ifdef STY_HEIGHT_FOG
	{
		// ∫ a·e^{-b(y - y0)} ds along the ray from the camera (closed form).
		vec3 ray = vFogWorldPos - cameraPosition;
		float dist = max( length( ray ), 1e-4 );
		vec3 rd = ray / dist;
		float b = uHFogFalloff;
		float k = b * rd.y;
		float atCam = uHFogDensity * exp( - b * ( cameraPosition.y - uHFogBase ) );
		float optical = abs( k ) > 1e-4 ? atCam * ( 1.0 - exp( - k * dist ) ) / k : atCam * dist;
		float hf = 1.0 - exp( - max( optical, 0.0 ) );
		// Forward scattering: haze glows towards the sun.
		float sunAmt = pow( max( dot( rd, uHFogSunDir ), 0.0 ), 6.0 );
		vec3 hazeCol = uHFogColor + uHFogSunColor * sunAmt * 0.35;
		float total = 1.0 - ( 1.0 - fogFactor ) * ( 1.0 - hf );
		styFogCol = mix( fogColor, hazeCol, hf / max( fogFactor + hf, 1e-4 ) );
		fogFactor = total;
	}
	#endif
	gl_FragColor.rgb = mix( gl_FragColor.rgb, styFogCol, fogFactor );
#endif
`;
}

/** Opts a built-in (unpatched) material into height fog. */
export function enableHeightFog(material) {
  material.defines = { ...(material.defines ?? {}), STY_HEIGHT_FOG: '' };
  const prev = material.onBeforeCompile;
  material.onBeforeCompile = (shader, renderer) => {
    Object.assign(shader.uniforms, heightFogUniforms);
    prev?.call(material, shader, renderer);
  };
  return material;
}

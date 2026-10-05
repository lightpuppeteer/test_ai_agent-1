import * as THREE from 'three';
import { sharedUniforms, SHARED_UNIFORMS_GLSL, NOISE_GLSL } from './common.glsl.js';

/**
 * Stylised "baked-light" material built by patching MeshLambertMaterial with
 * `onBeforeCompile`. Patching (instead of a from-scratch ShaderMaterial) keeps
 * everything three.js gives us for free: shadows, fog, instancing, skinning,
 * hemisphere light, tone mapping.
 *
 * What the patch changes:
 *  1. Direct light → wrapped diffuse + soft ramp: wide, flat lit areas and a
 *     smooth painted terminator with a warm band (no harsh PBR falloff).
 *  2. Albedo → low-frequency domain-warped "brush" noise in world space plus
 *     an optional local-height gradient that fakes baked contact occlusion.
 *  3. Optional world-space triplanar texturing (no UV stretching on boxes,
 *     arches, roofs — ideal for procedural architecture).
 *  4. Sky-tinted rim/fresnel that turns sun-coloured when back-lit.
 *  5. Optional vertex wind sway driven by the global wind uniforms.
 *
 * All variants are expressed through `defines`, so three.js' program cache
 * keys stay correct and identical variants share one GPU program.
 */
export function createStylizedMaterial({
  color = 0xffffff,
  map = null,
  triplanarScale = 0, // >0 enables triplanar mapping (texture repeats per metre)
  wrap = 0.45, // wrapped-diffuse amount (0 = Lambert)
  softness = 0.55, // ramp width; smaller = flatter, more "cel" lighting
  rim = 0.22,
  painterly = 0.1, // albedo brush-noise strength
  painterlyScale = 0.35, // brush noise frequency (1/m)
  heightGradient = null, // [yStart, yEnd, darkenAmount] in geometry space
  windSway = 0, // metres of sway at heightGradient top (foliage, cloth props)
  side = THREE.FrontSide,
  transparent = false,
  opacity = 1,
  vertexColors = false,
  name = 'Stylized',
} = {}) {
  const material = new THREE.MeshLambertMaterial({
    color,
    map,
    side,
    transparent,
    opacity,
    vertexColors,
    name,
  });

  material.defines = material.defines ?? {};
  if (triplanarScale > 0 && map) material.defines.STY_TRIPLANAR = '';
  if (windSway > 0) material.defines.STY_WIND = '';

  const local = {
    uStyWrap: { value: wrap },
    uStySoftness: { value: softness },
    uStyRim: { value: rim },
    uStyPainterly: { value: painterly },
    uStyPainterlyScale: { value: painterlyScale },
    uStyHeightGrad: { value: new THREE.Vector3(...(heightGradient ?? [0, 1, 0])) },
    uStyTriScale: { value: triplanarScale },
    uStyWindSway: { value: windSway },
  };
  material.userData.stylizedUniforms = local;

  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, sharedUniforms, local);
    patchStylizedVertex(shader);
    patchStylizedFragment(shader);
  };
  material.customProgramCacheKey = () => 'stylized-v1';
  return material;
}

/** Vertex patch — exported so other patched materials (sand) can reuse it. */
export function patchStylizedVertex(shader) {
  shader.vertexShader = shader.vertexShader
    .replace(
      '#include <common>',
      /* glsl */ `#include <common>
      ${SHARED_UNIFORMS_GLSL}
      uniform float uStyWindSway;
      uniform vec3 uStyHeightGrad;
      varying vec3 vStyWorldPos;
      varying vec3 vStyWorldNormal;
      varying float vStyLocalY;`,
    )
    .replace(
      '#include <begin_vertex>',
      /* glsl */ `#include <begin_vertex>
      vStyLocalY = transformed.y;
      #ifdef STY_WIND
      {
        // Sway grows with height inside the object; phase varies per world position
        // so neighbouring trees/plants never move in unison.
        vec4 swayOrigin = modelMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        #ifdef USE_INSTANCING
          swayOrigin = modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        #endif
        float h = clamp((transformed.y - uStyHeightGrad.x) / max(uStyHeightGrad.y - uStyHeightGrad.x, 1e-3), 0.0, 1.0);
        float ph = dot(swayOrigin.xz, vec2(0.21, 0.17));
        float gust = sin(uWindPhase * 1.7 + ph) * 0.6 + sin(uWindPhase * 3.9 + ph * 2.3 + transformed.x) * 0.25;
        vec3 windLocal = normalize(transpose(mat3(modelMatrix)) * uWindDir);
        transformed += windLocal * (uStyWindSway * h * h * uWindStrength * (0.65 + gust));
      }
      #endif`,
    )
    .replace(
      '#include <project_vertex>',
      /* glsl */ `#include <project_vertex>
      {
        vec4 styWp = vec4(transformed, 1.0);
        vec3 styN = objectNormal;
        #ifdef USE_BATCHING
          styWp = batchingMatrix * styWp;
          styN = mat3(batchingMatrix) * styN;
        #endif
        #ifdef USE_INSTANCING
          styWp = instanceMatrix * styWp;
          // Correct for non-uniform instance scale (same trick as three's defaultnormal_vertex).
          mat3 styIm = mat3(instanceMatrix);
          styN /= vec3(dot(styIm[0], styIm[0]), dot(styIm[1], styIm[1]), dot(styIm[2], styIm[2]));
          styN = styIm * styN;
        #endif
        vStyWorldPos = (modelMatrix * styWp).xyz;
        mat3 styMm = mat3(modelMatrix);
        styN /= vec3(dot(styMm[0], styMm[0]), dot(styMm[1], styMm[1]), dot(styMm[2], styMm[2]));
        vStyWorldNormal = normalize(styMm * styN);
      }`,
    );
}

/** Fragment patch — lighting model, brush noise, triplanar, rim. */
export function patchStylizedFragment(shader) {
  shader.fragmentShader = shader.fragmentShader
    .replace(
      '#include <common>',
      /* glsl */ `#include <common>
      ${SHARED_UNIFORMS_GLSL}
      ${NOISE_GLSL}
      uniform float uStyWrap;
      uniform float uStySoftness;
      uniform float uStyRim;
      uniform float uStyPainterly;
      uniform float uStyPainterlyScale;
      uniform vec3 uStyHeightGrad;
      uniform float uStyTriScale;
      varying vec3 vStyWorldPos;
      varying vec3 vStyWorldNormal;
      varying float vStyLocalY;`,
    )
    .replace(
      '#include <map_fragment>',
      /* glsl */ `
      #ifdef USE_MAP
        #ifdef STY_TRIPLANAR
          vec3 styBw = pow(abs(normalize(vStyWorldNormal)), vec3(4.0));
          styBw /= (styBw.x + styBw.y + styBw.z);
          vec3 styTp = vStyWorldPos * uStyTriScale;
          vec4 sampledDiffuseColor =
              texture2D(map, styTp.zy) * styBw.x +
              texture2D(map, styTp.xz) * styBw.y +
              texture2D(map, styTp.xy) * styBw.z;
        #else
          vec4 sampledDiffuseColor = texture2D(map, vMapUv);
        #endif
        diffuseColor *= sampledDiffuseColor;
      #endif`,
    )
    .replace(
      '#include <color_fragment>',
      /* glsl */ `#include <color_fragment>
      {
        // Broad painterly albedo variation (low frequency → reads as brushwork).
        float bn = styPainterly(vStyWorldPos * uStyPainterlyScale);
        float fn = styNoise3(vStyWorldPos * 2.3);
        diffuseColor.rgb *= 1.0 + uStyPainterly * ((bn - 0.5) * 2.0 + (fn - 0.5) * 0.6);
        diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(1.06, 0.99, 0.9), bn * uStyPainterly * 2.5);
        // Fake baked contact occlusion: darker (and slightly cooler) near the base.
        float hg = smoothstep(uStyHeightGrad.x, uStyHeightGrad.y, vStyLocalY);
        diffuseColor.rgb *= mix(vec3(1.0 - uStyHeightGrad.z) * vec3(0.95, 0.98, 1.04), vec3(1.0), hg);
      }`,
    )
    .replace(
      '#include <lights_lambert_pars_fragment>',
      /* glsl */ `
      varying vec3 vViewPosition;
      struct LambertMaterial {
        vec3 diffuseColor;
        float specularStrength;
      };
      // Accumulated, shadowed sun light (for sparkles / wet sheen in derived materials).
      vec3 styDirect = vec3(0.0);
      void RE_Direct_Lambert(const in IncidentLight directLight, const in vec3 geometryPosition,
          const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal,
          const in LambertMaterial material, inout ReflectedLight reflectedLight) {
        float ndl = dot(geometryNormal, directLight.direction);
        float wrapped = clamp((ndl + uStyWrap) / (1.0 + uStyWrap), 0.0, 1.0);
        // Soft ramp: lit side plateaus early (baked look), terminator stays smooth.
        float ramp = mix(wrapped, smoothstep(0.0, uStySoftness, wrapped), 0.75);
        // Warm band hugging the terminator, like light scattering in stucco.
        float band = smoothstep(0.0, 0.18, wrapped) * (1.0 - smoothstep(0.18, 0.5, wrapped));
        vec3 irradiance = directLight.color * (ramp + band * vec3(0.16, 0.06, -0.02));
        reflectedLight.directDiffuse += irradiance * BRDF_Lambert(material.diffuseColor);
        styDirect += directLight.color * clamp(ndl, 0.0, 1.0);
      }
      void RE_IndirectDiffuse_Lambert(const in vec3 irradiance, const in vec3 geometryPosition,
          const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal,
          const in LambertMaterial material, inout ReflectedLight reflectedLight) {
        reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert(material.diffuseColor);
      }
      #define RE_Direct RE_Direct_Lambert
      #define RE_IndirectDiffuse RE_IndirectDiffuse_Lambert
      `,
    )
    .replace(
      '#include <lights_fragment_end>',
      /* glsl */ `#include <lights_fragment_end>
      {
        vec3 wn = normalize(vStyWorldNormal);
        vec3 wv = normalize(cameraPosition - vStyWorldPos);
        float fres = pow(1.0 - clamp(dot(wn, wv), 0.0, 1.0), 4.0);
        float backLit = pow(clamp(dot(-wv, uSunDir), 0.0, 1.0), 3.0);
        vec3 rimCol = mix(uSkyHorizon * 0.6, uSunColor * 1.4, backLit);
        reflectedLight.indirectDiffuse += fres * uStyRim * rimCol * (0.5 + 0.5 * clamp(wn.y + 0.6, 0.0, 1.0));
      }`,
    );
}

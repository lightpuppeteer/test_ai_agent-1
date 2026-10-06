import * as THREE from 'three';
import { sharedUniforms, SHARED_UNIFORMS_GLSL, NOISE_GLSL } from './common.glsl.js';
import { heightFogUniforms } from '../lighting/ShaderPatches.js';

/**
 * Stylised PBR material: MeshStandardMaterial patched with `onBeforeCompile`.
 *
 * Patching keeps everything three.js provides — shadows, IBL from
 * `scene.environment` (diffuse irradiance + roughness-correct specular),
 * fog, instancing, skinning, morph targets, tone mapping — and only bends
 * the parts that make it look painted:
 *
 *  1. Direct light: GGX specular is untouched, but the *diffuse* term uses a
 *     wrapped, soft ramp with a warm terminator band (baked, low-frequency
 *     shading instead of a hard Lambert falloff).
 *  2. Albedo: low-frequency domain-warped "brush" noise in world space and an
 *     optional local-height gradient (fake contact darkening).
 *  3. Optional world-space triplanar texturing (no stretching on scaled
 *     instanced boxes, arches), roof-plane mapping (tile courses follow
 *     each roof face) or plain UVs — for the albedo *and* a packed detail
 *     map (normal XY, roughness factor, cavity; see textures/TextureSynth.js)
 *     that adds relief, varied glossiness and baked micro-occlusion.
 *  4. Optional per-vertex baked AO (`aAO`, see lighting/VertexAO.js) applied
 *     to indirect diffuse + specular occlusion, like an aoMap.
 *  5. Sky/sun rim light, optional vertex wind sway, height fog.
 *
 * Variants are expressed with `defines` so program caching stays correct.
 * `patch(shader)` lets derived materials (sand, garments) inject more code.
 */
export function createStylizedMaterial({
  color = 0xffffff,
  map = null,
  roughness = 0.88,
  metalness = 0,
  emissive = 0x000000,
  triplanarScale = 0, // >0 enables triplanar mapping (texture repeats per metre)
  roofMapping = false, // with triplanarScale: map along each roof plane instead
  detailMap = null, // packed detail texture (RG normal, B roughness/2, A cavity)
  normalScale = 1, // detail normal strength
  cavity = 0.7, // how much the detail cavity darkens albedo
  detailRepeat = [1, 1], // UV mode: detail repeats per map UV unit
  wrap = 0.45, // wrapped-diffuse amount (0 = Lambert)
  softness = 0.55, // ramp width; smaller = flatter, more "cel" lighting
  rim = 0.16,
  painterly = 0.1, // albedo brush-noise strength
  painterlyScale = 0.35, // brush noise frequency (1/m)
  heightGradient = null, // [yStart, yEnd, darkenAmount] in geometry space
  windSway = 0, // metres of sway at heightGradient top (foliage, cloth props)
  vertexAO = false, // use the baked `aAO` attribute
  aoIntensity = 1,
  envMapIntensity = 1,
  side = THREE.FrontSide,
  transparent = false,
  opacity = 1,
  vertexColors = false,
  polygonOffset = false,
  alphaTest = 0,
  uniforms = {}, // extra uniforms for `patch`
  defines = {},
  patch = null, // (shader) => void, runs after the stylised patch
  cacheKey = '', // must differ whenever `patch` produces different code
  name = 'Stylized',
} = {}) {
  const material = new THREE.MeshStandardMaterial({
    color,
    map,
    roughness,
    metalness,
    emissive,
    envMapIntensity,
    side,
    transparent,
    opacity,
    vertexColors,
    alphaTest,
    name,
  });
  if (polygonOffset) {
    material.polygonOffset = true;
    material.polygonOffsetFactor = -1;
    material.polygonOffsetUnits = -2;
  }

  material.defines = { ...(material.defines ?? {}), STY_HEIGHT_FOG: '', ...defines };
  const worldMapped = triplanarScale > 0 && (map || detailMap);
  if (worldMapped) material.defines[roofMapping ? 'STY_ROOFMAP' : 'STY_TRIPLANAR'] = '';
  if (detailMap && (worldMapped || map)) material.defines.STY_DETAIL = '';
  if (windSway > 0) material.defines.STY_WIND = '';
  if (vertexAO) material.defines.STY_VERTEX_AO = '';

  const local = {
    uStyWrap: { value: wrap },
    uStySoftness: { value: softness },
    uStyRim: { value: rim },
    uStyPainterly: { value: painterly },
    uStyPainterlyScale: { value: painterlyScale },
    uStyHeightGrad: { value: new THREE.Vector3(...(heightGradient ?? [0, 1, 0])) },
    uStyTriScale: { value: triplanarScale },
    uStyWindSway: { value: windSway },
    uStyAOIntensity: { value: aoIntensity },
    uStyDetail: { value: detailMap },
    uStyNormalScale: { value: normalScale },
    uStyCavity: { value: cavity },
    uStyDetailRepeat: { value: new THREE.Vector2(...detailRepeat) },
    ...uniforms,
  };
  material.userData.stylizedUniforms = local;

  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, sharedUniforms, heightFogUniforms, local);
    patchStylizedVertex(shader);
    patchStylizedFragment(shader);
    patch?.(shader);
  };
  material.customProgramCacheKey = () => `stylized-pbr-v3|${cacheKey}`;
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
      varying float vStyLocalY;
      #ifdef STY_VERTEX_AO
        attribute float aAO;
        varying float vStyAO;
      #endif`,
    )
    .replace(
      '#include <begin_vertex>',
      /* glsl */ `#include <begin_vertex>
      vStyLocalY = transformed.y;
      #ifdef STY_VERTEX_AO
        vStyAO = aAO;
      #endif
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
        #ifdef USE_INSTANCING
          windLocal = normalize(transpose(mat3(instanceMatrix)) * windLocal);
        #endif
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

/** Fragment patch — stylised direct diffuse, brush noise, triplanar, baked AO, rim. */
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
      uniform float uStyAOIntensity;
      varying vec3 vStyWorldPos;
      varying vec3 vStyWorldNormal;
      varying float vStyLocalY;
      #ifdef STY_VERTEX_AO
        varying float vStyAO;
      #endif
      #ifdef STY_DETAIL
        uniform sampler2D uStyDetail;
        uniform float uStyNormalScale;
        uniform float uStyCavity;
        uniform vec2 uStyDetailRepeat;
      #endif
      #ifdef STY_ROOFMAP
        // Roof-plane mapping: u runs along the eave, v up the slope (metres),
        // so tile courses follow every face of a hip roof.
        vec2 styRoofUV(vec3 n, vec3 p, out vec3 T, out vec3 B) {
          vec2 h = n.xz;
          float hl = max(length(h), 1e-3);
          h /= hl;
          T = vec3(-h.y, 0.0, h.x);
          B = normalize(cross(n, T));
          if (B.y < 0.0) B = -B;
          return vec2(dot(p.xz, T.xz), p.y / max(hl, 0.25));
        }
      #endif
      #if defined(STY_DETAIL) && !defined(STY_TRIPLANAR) && !defined(STY_ROOFMAP)
        // Tangent frame from screen-space derivatives (no tangent attribute needed).
        mat3 styTangentFrame(vec3 eyePos, vec3 n, vec2 uv) {
          vec3 q0 = dFdx(eyePos);
          vec3 q1 = dFdy(eyePos);
          vec2 st0 = dFdx(uv);
          vec2 st1 = dFdy(uv);
          vec3 q1perp = cross(q1, n);
          vec3 q0perp = cross(n, q0);
          vec3 T = q1perp * st0.x + q0perp * st1.x;
          vec3 B = q1perp * st0.y + q0perp * st1.y;
          float det = max(dot(T, T), dot(B, B));
          float scale = det == 0.0 ? 0.0 : inversesqrt(det);
          return mat3(T * scale, B * scale, n);
        }
      #endif`,
    )
    .replace(
      '#include <map_fragment>',
      /* glsl */ `
      #ifdef STY_ROOFMAP
        vec3 styRoofT;
        vec3 styRoofB;
        vec2 styRoofCoord = styRoofUV(normalize(vStyWorldNormal), vStyWorldPos, styRoofT, styRoofB) * uStyTriScale;
      #endif
      #ifdef USE_MAP
        #if defined(STY_ROOFMAP)
          vec4 sampledDiffuseColor = texture2D(map, styRoofCoord);
        #elif defined(STY_TRIPLANAR)
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
      }
      #ifdef STY_DETAIL
        vec4 styDet;
        vec3 styDetW = vec3(0.0); // world-space normal offset (triplanar / roof)
        vec2 styDetT = vec2(0.0); // tangent-space XY (UV mode)
        {
          #if defined(STY_ROOFMAP)
            styDet = texture2D(uStyDetail, styRoofCoord);
            vec2 tn = styDet.rg * 2.0 - 1.0;
            styDetW = styRoofT * tn.x + styRoofB * tn.y;
          #elif defined(STY_TRIPLANAR)
            vec3 nW = normalize(vStyWorldNormal);
            vec3 bw = pow(abs(nW), vec3(4.0));
            bw /= (bw.x + bw.y + bw.z);
            vec3 tp = vStyWorldPos * uStyTriScale;
            vec4 dX = texture2D(uStyDetail, tp.zy);
            vec4 dY = texture2D(uStyDetail, tp.xz);
            vec4 dZ = texture2D(uStyDetail, tp.xy);
            vec2 tX = dX.rg * 2.0 - 1.0;
            vec2 tY = dY.rg * 2.0 - 1.0;
            vec2 tZ = dZ.rg * 2.0 - 1.0;
            // Each projection's tangent axes are world axes (no mirroring),
            // so the height gradient maps straight onto the surface (UDN blend).
            styDetW = vec3(0.0, tX.y, tX.x) * bw.x + vec3(tY.x, 0.0, tY.y) * bw.y + vec3(tZ.x, tZ.y, 0.0) * bw.z;
            styDet = dX * bw.x + dY * bw.y + dZ * bw.z;
          #else
            styDet = texture2D(uStyDetail, vMapUv * uStyDetailRepeat);
            styDetT = styDet.rg * 2.0 - 1.0;
          #endif
        }
        diffuseColor.rgb *= mix(1.0, styDet.a, uStyCavity);
      #endif`,
    )
    .replace(
      '#include <roughnessmap_fragment>',
      /* glsl */ `#include <roughnessmap_fragment>
      #ifdef STY_DETAIL
        roughnessFactor = clamp(roughnessFactor * styDet.b * 2.0, 0.03, 1.0);
      #endif`,
    )
    .replace(
      '#include <normal_fragment_maps>',
      /* glsl */ `#include <normal_fragment_maps>
      #ifdef STY_DETAIL
        #if defined(STY_ROOFMAP) || defined(STY_TRIPLANAR)
        {
          vec3 nW = normalize(vStyWorldNormal);
          #ifdef DOUBLE_SIDED
            nW *= faceDirection;
          #endif
          normal = normalize((viewMatrix * vec4(normalize(nW + styDetW * uStyNormalScale), 0.0)).xyz);
        }
        #else
        {
          mat3 tbn = styTangentFrame(-vViewPosition, normal, vMapUv * uStyDetailRepeat);
          #ifdef DOUBLE_SIDED
            tbn[0] *= faceDirection;
            tbn[1] *= faceDirection;
          #endif
          normal = normalize(tbn * vec3(styDetT * uStyNormalScale, 1.0));
        }
        #endif
      #endif`,
    )
    .replace(
      '#include <lights_physical_pars_fragment>',
      /* glsl */ `#include <lights_physical_pars_fragment>
      // Accumulated, shadowed sun light (sparkles / wet sheen in derived materials).
      vec3 styDirect = vec3(0.0);
      // Physical GGX specular + stylised wrapped diffuse. (Clearcoat/sheen
      // are not used by stylised materials and are intentionally omitted.)
      void RE_Direct_Stylized(const in IncidentLight directLight, const in vec3 geometryPosition,
          const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal,
          const in PhysicalMaterial material, inout ReflectedLight reflectedLight) {
        float ndl = dot(geometryNormal, directLight.direction);
        float dotNL = saturate(ndl);
        vec3 specularBRDF = BRDF_GGX(directLight.direction, geometryViewDir, geometryNormal, material);
        reflectedLight.directSpecular += dotNL * directLight.color * specularBRDF * material.multiScatteringCompensation;
        vec3 halfDir = normalize(directLight.direction + geometryViewDir);
        vec3 F = F_Schlick(material.specularColor, material.specularF90, saturate(dot(geometryViewDir, halfDir)));
        float wrapped = clamp((ndl + uStyWrap) / (1.0 + uStyWrap), 0.0, 1.0);
        // Soft ramp: lit side plateaus early (baked look), terminator stays smooth.
        float ramp = mix(wrapped, smoothstep(0.0, uStySoftness, wrapped), 0.75);
        // Warm band hugging the terminator, like light scattering in stucco/skin.
        float band = smoothstep(0.0, 0.18, wrapped) * (1.0 - smoothstep(0.18, 0.5, wrapped));
        vec3 irradiance = directLight.color * (ramp + band * vec3(0.16, 0.06, -0.02));
        reflectedLight.directDiffuse += irradiance * BRDF_Lambert(material.diffuseContribution) * (1.0 - F);
        styDirect += directLight.color * dotNL;
      }
      #undef RE_Direct
      #define RE_Direct RE_Direct_Stylized`,
    )
    .replace(
      '#include <lights_fragment_end>',
      /* glsl */ `#include <lights_fragment_end>
      {
        vec3 wn = inverseTransformDirection(normal, viewMatrix); // includes detail relief
        vec3 wv = normalize(cameraPosition - vStyWorldPos);
        float fres = pow(1.0 - clamp(dot(wn, wv), 0.0, 1.0), 4.0);
        float backLit = pow(clamp(dot(-wv, uSunDir), 0.0, 1.0), 3.0);
        vec3 rimCol = mix(uSkyHorizon * 0.6, uSunColor * 1.4, backLit);
        reflectedLight.indirectDiffuse += fres * uStyRim * rimCol * (0.5 + 0.5 * clamp(wn.y + 0.6, 0.0, 1.0));
      }`,
    )
    .replace(
      '#include <aomap_fragment>',
      /* glsl */ `#include <aomap_fragment>
      #ifdef STY_VERTEX_AO
      {
        float styAO = mix(1.0, vStyAO, uStyAOIntensity);
        reflectedLight.indirectDiffuse *= styAO;
        float styNV = saturate(dot(geometryNormal, geometryViewDir));
        reflectedLight.indirectSpecular *= computeSpecularOcclusion(styNV, styAO, material.roughness);
        // A touch of direct occlusion sells the baked look in deep corners.
        reflectedLight.directDiffuse *= mix(1.0, styAO, 0.3);
      }
      #endif`,
    );
}

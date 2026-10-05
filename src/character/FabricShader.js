import * as THREE from 'three';

/**
 * Procedural fabric relief for garments — no textures, no UV unwrap.
 *
 * Skinned garments are textured in *bind space*: the rest-pose `position`
 * attribute is stable under skinning, so a pattern evaluated on it sticks
 * to the cloth however the character moves (2D weaves are projected
 * triplanar-style on the bind-space normal). Verlet cloth has no stable
 * positions, so it uses its UVs scaled to metres instead.
 *
 * Each pattern is a height in metres turned into a normal with Mikkelsen's
 * surface-gradient bump (screen-space derivatives, unnormalised so the relief
 * is physically scaled). Every octave fades out by its frequency × pixel
 * footprint, so fine weaves show in close-ups and never alias at distance,
 * while the broad wrinkles carry the read at gameplay range.
 *
 * Kinds: cotton (plain weave), denim (twill), wool (rib knit), leather
 * (pebbled, creased), satin (long soft folds), lycra (fine rib), hair
 * (strand grooves + tonal streaks).
 */
export const FABRIC_KINDS = ['cotton', 'denim', 'wool', 'leather', 'satin', 'lycra', 'hair'];

const HEADER = /* glsl */ `
  varying vec3 vFabP;
  varying vec3 vFabN;
  uniform float uFabricStrength;
  float fabFade(float freq, float px) { return 1.0 - smoothstep(0.3, 0.7, freq * px); }
  float fabWeave(vec2 c) { return sin(6.2831853 * c.x) * sin(6.2831853 * c.y) * 0.5 + 0.5; }
  float fabTwill(vec2 c) { return sin(6.2831853 * (c.x + c.y)) * 0.5 + 0.5; }
  float fabRib(vec2 c) { return abs(sin(3.14159265 * c.x)); }
  #ifdef FAB_UV
    #define FAB2(fn, f) fn(fabP.xy * (f))
  #else
    #define FAB2(fn, f) (fn(fabP.zy * (f)) * fabW.x + fn(fabP.xz * (f)) * fabW.y + fn(fabP.xy * (f)) * fabW.z)
  #endif
`;

const BODY = /* glsl */ `
  float fabH = 0.0;
  {
    vec3 fabP = vFabP;
    vec3 fabW = pow(abs(normalize(vFabN)), vec3(4.0));
    fabW /= (fabW.x + fabW.y + fabW.z);
    float px = max(length(fwidth(fabP)), 1e-5);
    // Broad wrinkles: compression folds (stretched across) + soft creases.
    float wr = styNoise3(fabP * vec3(9.0, 26.0, 9.0)) * 0.65 + styNoise3(fabP * 17.0 + 3.1) * 0.35;
    float wf = fabFade(26.0, px);
    float tone = 1.0;
    #if defined(FAB_COTTON)
      float f = fabFade(600.0, px);
      float weave = FAB2(fabWeave, 600.0);
      fabH = (wr - 0.5) * 0.0045 * wf + (weave - 0.5) * 0.00022 * f;
      tone = 1.0 - 0.07 * (1.0 - weave) * f;
    #elif defined(FAB_DENIM)
      float f = fabFade(420.0, px);
      float twill = FAB2(fabTwill, 420.0);
      fabH = (wr - 0.5) * 0.005 * wf + (twill - 0.5) * 0.0003 * f;
      tone = 0.94 + 0.12 * (twill - 0.5) * f + 0.08 * (styNoise3(fabP * 40.0) - 0.5);
    #elif defined(FAB_WOOL)
      float f = fabFade(150.0, px);
      float rib = FAB2(fabRib, 150.0);
      float fuzz = styNoise3(fabP * 900.0) * fabFade(900.0, px);
      fabH = (wr - 0.5) * 0.005 * wf + rib * 0.0007 * f + fuzz * 0.00012;
      tone = 0.92 + 0.1 * rib * f;
    #elif defined(FAB_LEATHER)
      float f = fabFade(700.0, px);
      float pebble = smoothstep(0.35, 0.65, styNoise3(fabP * 700.0));
      float crease = sin(fabP.y * 190.0 + styNoise3(fabP * 30.0) * 5.0) * 0.5 + 0.5;
      fabH = pebble * 0.00018 * f + crease * 0.0008 * fabFade(30.0, px) + (wr - 0.5) * 0.0015 * wf;
      tone = 0.92 + 0.12 * pebble * f;
    #elif defined(FAB_SATIN)
      float folds = styNoise3(fabP * vec3(10.0, 3.0, 10.0)) * 0.7 + styNoise3(fabP * vec3(24.0, 6.0, 24.0)) * 0.3;
      fabH = (folds - 0.5) * 0.006 * fabFade(24.0, px);
    #elif defined(FAB_LYCRA)
      float f = fabFade(500.0, px);
      fabH = FAB2(fabRib, 500.0) * 0.00012 * f + (wr - 0.5) * 0.0008 * wf;
    #elif defined(FAB_HAIR)
      // Strands run down from the crown: grooves around the head's vertical axis.
      vec2 d = fabP.xz - vec2(0.0, 0.015);
      float a = atan(d.x, d.y);
      float clump = styNoise3(fabP * 22.0);
      float strands = sin(a * 150.0 + clump * 7.0) * 0.5 + 0.5;
      float f = fabFade(250.0, px);
      fabH = strands * 0.0009 * f + (clump - 0.5) * 0.003 * fabFade(22.0, px);
      tone = 0.86 + 0.26 * strands * f + 0.18 * (clump - 0.5);
    #endif
    diffuseColor.rgb *= tone;
  }
`;

const NORMAL = /* glsl */ `
  {
    // Surface-gradient bump (Mikkelsen 2010), unnormalised: fabH is in metres.
    vec3 sx = dFdx(-vViewPosition);
    vec3 sy = dFdy(-vViewPosition);
    vec2 dH = vec2(dFdx(fabH), dFdy(fabH)) * uFabricStrength;
    vec3 R1 = cross(sy, normal);
    vec3 R2 = cross(normal, sx);
    float det = dot(sx, R1);
    if (abs(det) > 1e-14) normal = normalize(normal - (dH.x * R1 + dH.y * R2) / det);
  }
`;

/**
 * @param {string} kind one of FABRIC_KINDS
 * @param {object} [o]
 * @param {[number, number]|null} [o.uvScale] metres per UV unit (Verlet cloth); null = bind space
 * @param {number} [o.strength]
 * @returns {{ patch: (shader) => void, uniforms: object, defines: object, cacheKey: string }}
 */
export function fabric(kind, { uvScale = null, strength = 1 } = {}) {
  if (!FABRIC_KINDS.includes(kind)) throw new Error(`Unknown fabric "${kind}"`);
  const defines = { [`FAB_${kind.toUpperCase()}`]: '' };
  if (uvScale) defines.FAB_UV = '';
  const uniforms = {
    uFabricStrength: { value: strength },
    uFabricScale: { value: new THREE.Vector2(...(uvScale ?? [1, 1])) },
  };
  const patch = (shader) => {
    shader.vertexShader = shader.vertexShader
      .replace(
        '#include <common>',
        '#include <common>\nvarying vec3 vFabP;\nvarying vec3 vFabN;\nuniform vec2 uFabricScale;',
      )
      .replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
        #ifdef FAB_UV
          vFabP = vec3(uv * uFabricScale, 0.0);
          vFabN = vec3(0.0, 0.0, 1.0);
        #else
          vFabP = position; // bind pose: stable under skinning
          vFabN = normal;
        #endif`,
      );
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>\n${HEADER}`)
      .replace('#include <color_fragment>', `#include <color_fragment>\n${BODY}`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>\n${NORMAL}`);
  };
  return { patch, uniforms, defines, cacheKey: `fabric:${kind}${uvScale ? ':uv' : ''};` };
}

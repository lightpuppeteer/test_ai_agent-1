import { WORLD } from '../config.js';

/**
 * Single source of truth for the beach shape.
 *
 * The sand mesh is displaced *in the vertex shader* (GLSL), while physics
 * needs the same surface on the CPU (heightfield collider, towel placement,
 * ocean shore attenuation, buoyancy). Both implementations are generated from
 * the parameters below, so they can never drift apart.
 */
export const TERRAIN = {
  hBack: 2.95, // sand height where the beach meets the promenade (z = zBack)
  zBack: WORLD.promenade.zSea,
  // Base profile: h(d) = hBack - a·d - b·d², d = distance from the promenade.
  // Tuned so the dry/wet line sits near z ≈ 25 and z = 120 is ~6 m deep.
  a: 0.032755,
  b: 0.0001351,
  // Dunes only live on the dry upper beach, fading out at both ends.
  duneMask: { start: 4, full: 16, fadeStart: 38, fadeEnd: 58 },
  dunes: [
    // dir (unit), freq (rad/m), amp (m), phase (rad)
    { dir: [0.83, 0.557], freq: 0.28, amp: 0.45, phase: 0.7 },
    { dir: [-0.42, 0.907], freq: 0.19, amp: 0.6, phase: 2.1 },
    { dir: [0.97, -0.243], freq: 0.47, amp: 0.16, phase: 4.2 },
  ],
  duneSharpness: 1.6, // >1 widens troughs, sharpens crests
  duneBias: 0.35, // subtracted (× mask) so dunes don't lift the whole beach
  warp: { freq: 0.043, amp: 6.0 }, // organic domain warp
  ampVariation: { freq: 0.021, amount: 0.45 }, // dunes grow/shrink along the beach
};

const smoothstep = (e0, e1, x) => {
  const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1);
  return t * t * (3 - 2 * t);
};

/** CPU sand height (metres) at world (x, z). Mirrors SAND_HEIGHT_GLSL exactly. */
export function sandHeight(x, z) {
  const T = TERRAIN;
  const d = Math.max(z - T.zBack, 0);
  const base = T.hBack - T.a * d - T.b * d * d;

  const m = T.duneMask;
  const mask = smoothstep(m.start, m.full, d) * (1 - smoothstep(m.fadeStart, m.fadeEnd, d));
  if (mask <= 0) return base;

  const wx = x + T.warp.amp * Math.sin(z * T.warp.freq + 1.3);
  const wz = z + T.warp.amp * Math.sin(x * T.warp.freq * 1.3 + 0.4);
  const av = 1 - T.ampVariation.amount * 0.5 + T.ampVariation.amount * 0.5 * Math.sin(x * T.ampVariation.freq + 0.9);

  let dunes = 0;
  for (const w of T.dunes) {
    const s = 0.5 + 0.5 * Math.sin((w.dir[0] * wx + w.dir[1] * wz) * w.freq + w.phase);
    dunes += w.amp * Math.pow(s, T.duneSharpness);
  }
  return base + mask * (av * dunes - T.duneBias);
}

/** Surface normal by central differences (writes into `out` = {x,y,z}). */
export function sandNormal(x, z, out = { x: 0, y: 1, z: 0 }, eps = 0.25) {
  const hx = sandHeight(x + eps, z) - sandHeight(x - eps, z);
  const hz = sandHeight(x, z + eps) - sandHeight(x, z - eps);
  const nx = -hx;
  const ny = 2 * eps;
  const nz = -hz;
  const len = Math.hypot(nx, ny, nz);
  out.x = nx / len;
  out.y = ny / len;
  out.z = nz / len;
  return out;
}

const f = (v) => {
  const s = Number(v).toFixed(7);
  return s.includes('.') ? s : `${s}.0`;
};

/** GLSL twin of sandHeight(), generated from TERRAIN. */
export const SAND_HEIGHT_GLSL = (() => {
  const T = TERRAIN;
  const m = T.duneMask;
  const duneTerms = T.dunes
    .map(
      (w) =>
        `dunes += ${f(w.amp)} * pow(0.5 + 0.5 * sin((${f(w.dir[0])} * wx + ${f(w.dir[1])} * wz) * ${f(
          w.freq,
        )} + ${f(w.phase)}), ${f(T.duneSharpness)});`,
    )
    .join('\n    ');
  return /* glsl */ `
  float sandHeight(vec2 p) {
    float d = max(p.y - ${f(T.zBack)}, 0.0);
    float base = ${f(T.hBack)} - ${f(T.a)} * d - ${f(T.b)} * d * d;
    float mask = smoothstep(${f(m.start)}, ${f(m.full)}, d) * (1.0 - smoothstep(${f(m.fadeStart)}, ${f(m.fadeEnd)}, d));
    if (mask <= 0.0) return base;
    float wx = p.x + ${f(T.warp.amp)} * sin(p.y * ${f(T.warp.freq)} + 1.3);
    float wz = p.y + ${f(T.warp.amp)} * sin(p.x * ${f(T.warp.freq * 1.3)} + 0.4);
    float av = ${f(1 - T.ampVariation.amount * 0.5)} + ${f(T.ampVariation.amount * 0.5)} * sin(p.x * ${f(
      T.ampVariation.freq,
    )} + 0.9);
    float dunes = 0.0;
    ${duneTerms}
    return base + mask * (av * dunes - ${f(T.duneBias)});
  }
  `;
})();

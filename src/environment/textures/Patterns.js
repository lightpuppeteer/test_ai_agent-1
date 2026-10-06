import {
  mulberry32,
  hash2,
  createNoise,
  createCells,
  createImage,
  shade,
  bake,
  runningBond,
  roundedRectSDF,
  crackMask,
  smoothstep,
  mix,
  clamp01,
} from './TextureSynth.js';

/**
 * Procedural material library. Each function returns a baked texture set
 * `{ S, albedo, detail }` (see TextureSynth.bake). Albedo is authored near
 * white wherever the hue should come from the material colour (one granite
 * texture serves light and dark stone), and in colour where the pattern *is*
 * the colour (azulejos, window interiors).
 *
 * Tile sizes match the world-space mapping scale used by the materials so
 * the baked normals have physically consistent relief.
 */

const TAU = Math.PI * 2;
const fract = (x) => x - Math.floor(x);

function setGrey(p, t, warm = 0) {
  p.r = t * (1 + warm);
  p.g = t;
  p.b = t * (1 - warm);
}

/** Granite ashlar: rusticated blocks, chisel marks, mica specks, grimy joints. 2 m tile. */
export function ashlar({ S = 1024, seed = 11 } = {}) {
  const rnd = mulberry32(seed);
  const N = createNoise(seed);
  const N2 = createNoise(seed + 5);
  const lookup = runningBond(rnd, 6, { minBlocks: 3, maxBlocks: 5, irregular: 0.8 });
  const joint = 0.0045;
  const bevel = 0.014;
  const img = shade(createImage(S), (p, u, v) => {
    const b = lookup(u, v);
    const blk = b.block;
    const inside = -roundedRectSDF(b.px, b.py, b.halfW - joint, b.halfH - joint, 0.01);
    const grain = N.fbm(u, v, 96, 3);
    if (inside <= 0) {
      const m = N2.fbm(u, v, 160, 2);
      p.h = 0.06 + m * 0.08;
      setGrey(p, 0.66 + m * 0.1, 0.03);
      p.rough = 1.15;
      return;
    }
    const bev = smoothstep(0, bevel, inside);
    const nx = b.px / b.halfW;
    const ny = b.py / b.halfH;
    const pillow = 1 - 0.22 * (nx * nx + ny * ny);
    const dir = b.px * Math.cos(blk.angle) + b.py * Math.sin(blk.angle);
    const chisel = Math.sin(dir * TAU * 70 + grain * 7) * 0.5 + 0.5;
    p.h = 0.22 + 0.62 * bev * pillow + 0.09 * grain + 0.035 * chisel * bev;
    const speck = N2.noise(u * 384, v * 384, 384);
    let t = (0.8 + blk.tone * 0.17) * (0.9 + 0.14 * N2.fbm(u, v, 12, 4));
    if (speck > 0.86) t += 0.07;
    else if (speck < 0.1) t *= 0.6;
    t *= 0.84 + 0.16 * smoothstep(0, bevel * 2.5, inside);
    t *= 1 - 0.1 * smoothstep(0.55, 0.8, N.fbm2(u, v, 24, 2, 3));
    setGrey(p, t, (blk.hue - 0.5) * 0.07);
    p.rough = speck > 0.86 ? 0.72 : 0.95 + 0.12 * (1 - bev);
  });
  return bake(img, { tileSize: 2, depth: 0.035, cavityRadius: 4 });
}

/** Lime-washed stucco: trowel waves, sand grain, cracks, flaked patches, drips. 3 m tile. */
export function stucco({ S = 1024, seed = 23 } = {}) {
  const rnd = mulberry32(seed);
  const N = createNoise(seed);
  const N2 = createNoise(seed + 3);
  const N3 = createNoise(seed + 9);
  const cracks = crackMask(S, rnd, 5, { length: 0.16, width: 0.75, wander: 0.55 });
  const img = shade(createImage(S), (p, u, v, x, y, i) => {
    const trowel = N.fbm(u, v, 5, 4);
    const sand = N2.fbm(u, v, 220, 2);
    const flake = N3.fbm(u, v, 3, 5);
    const flakeIn = smoothstep(0.77, 0.785, flake) * 0.85;
    const lip = smoothstep(0.75, 0.77, flake) * 0.85 - flakeIn;
    let h = 0.6 + 0.3 * (trowel - 0.5) + 0.05 * sand + 0.08 * lip;
    let t = 0.95 - 0.07 * N2.fbm(u, v, 8, 3) - 0.03 * (1 - trowel);
    // Rain streaks below sills and cornices (vertical, gated by low-frequency noise).
    const drip = smoothstep(0.58, 0.82, N3.fbm2(u, v, 48, 3, 3)) * smoothstep(0.42, 0.7, N.fbm(u, v, 3, 2));
    t *= 1 - 0.13 * drip;
    let rough = 1.02 + 0.08 * sand;
    let r = t;
    let g = t;
    let b = t * 0.985;
    if (flakeIn > 0) {
      // Exposed rubble masonry where the render has fallen off.
      const rub = N2.fbm(u, v, 40, 4);
      const stones = smoothstep(0.35, 0.6, rub);
      h = mix(h, 0.15 + 0.25 * stones, flakeIn);
      // Subdued: reads as weathering, not as spots, when the tile repeats.
      const s = 0.8 + 0.12 * stones;
      r = mix(r, s * 0.95, flakeIn);
      g = mix(g, s * 0.91, flakeIn);
      b = mix(b, s * 0.86, flakeIn);
      rough = mix(rough, 1.2, flakeIn);
    }
    const c = cracks[i];
    h -= 0.25 * c;
    const ct = 1 - 0.3 * c;
    p.h = h;
    p.r = r * ct;
    p.g = g * ct;
    p.b = b * ct;
    p.rough = rough;
  });
  return bake(img, { tileSize: 3, depth: 0.02, cavityRadius: 3, cavityStrength: 1.2 });
}

/** Granite setts (paralelepípedos): domed, worn-smooth tops, sandy joints with moss. 1.67 m tile. */
export function setts({ S = 1024, seed = 37 } = {}) {
  const rnd = mulberry32(seed);
  const N = createNoise(seed);
  const N2 = createNoise(seed + 7);
  const lookup = runningBond(rnd, 11, { minBlocks: 7, maxBlocks: 9, irregular: 0.55 });
  const joint = 0.007;
  const img = shade(createImage(S), (p, u, v) => {
    const b = lookup(u, v);
    const blk = b.block;
    const inside = -roundedRectSDF(b.px, b.py, b.halfW - joint, b.halfH - joint, 0.02);
    const grain = N.fbm(u, v, 128, 2);
    if (inside <= 0) {
      const sand = N2.fbm(u, v, 200, 2);
      const moss = smoothstep(0.68, 0.78, N.fbm(u, v, 10, 3)) * 0.7;
      p.h = 0.05 + 0.1 * sand;
      p.r = mix(0.52, 0.5, moss) * (0.85 + 0.25 * sand);
      p.g = mix(0.48, 0.56, moss) * (0.85 + 0.25 * sand);
      p.b = mix(0.42, 0.38, moss) * (0.85 + 0.25 * sand);
      p.rough = 1.2;
      return;
    }
    const nx = b.px / b.halfW;
    const ny = b.py / b.halfH;
    const dome = smoothstep(0, 0.028, inside) * (1 - 0.35 * (nx * nx + ny * ny));
    // Small chips and dents.
    const dent = smoothstep(0.82, 0.92, N2.noise(u * 90, v * 90, 90)) * 0.12;
    p.h = 0.15 + 0.78 * dome + 0.05 * grain - dent;
    const polish = smoothstep(0.7, 0.92, p.h);
    const speck = N2.noise(u * 420, v * 420, 420);
    let t = 0.8 + blk.tone * 0.15;
    if (speck > 0.87) t += 0.05;
    else if (speck < 0.1) t *= 0.7;
    t *= 0.86 + 0.14 * smoothstep(0, 0.035, inside);
    t *= 0.95 + 0.1 * polish;
    setGrey(p, t, (blk.hue - 0.5) * 0.1);
    p.rough = 1.02 - 0.38 * polish;
  });
  return bake(img, { tileSize: 1.67, depth: 0.03, cavityRadius: 4 });
}

/** Promenade slabs: large sandstone-like flags, thin joints, the odd crack and stain. 3 m tile. */
export function paving({ S = 1024, seed = 41 } = {}) {
  const rnd = mulberry32(seed);
  const N = createNoise(seed);
  const N2 = createNoise(seed + 2);
  const lookup = runningBond(rnd, 5, { minBlocks: 2, maxBlocks: 4, irregular: 0.5 });
  const cracks = crackMask(S, rnd, 5, { length: 0.12, width: 0.9, wander: 0.35 });
  const joint = 0.0018;
  const img = shade(createImage(S), (p, u, v, x, y, i) => {
    const b = lookup(u, v);
    const blk = b.block;
    const inside = -roundedRectSDF(b.px, b.py, b.halfW - joint, b.halfH - joint, 0.003);
    const fine = N.fbm(u, v, 180, 3);
    if (inside <= 0) {
      p.h = 0.1;
      setGrey(p, 0.6, 0.04);
      p.rough = 1.2;
      return;
    }
    const bev = smoothstep(0, 0.005, inside);
    const tilt = (b.px * (blk.seed - 0.5) + b.py * (blk.angle / Math.PI - 0.5)) * 0.8;
    p.h = 0.3 + 0.55 * bev + 0.06 * fine + tilt;
    const stain = smoothstep(0.62, 0.8, N2.fbm(u, v, 7, 4));
    let t = (0.84 + blk.tone * 0.14) * (0.93 + 0.1 * N2.fbm(u, v, 30, 3));
    t *= 1 - 0.14 * stain;
    t *= 0.9 + 0.1 * smoothstep(0, 0.008, inside);
    const c = blk.seed < 0.35 ? cracks[i] : 0;
    p.h -= 0.3 * c;
    t *= 1 - 0.4 * c;
    setGrey(p, t, (blk.hue - 0.5) * 0.05 + 0.02);
    p.rough = 1.0 - 0.12 * stain + 0.05 * fine;
  });
  return bake(img, { tileSize: 3, depth: 0.02, cavityRadius: 3 });
}

/**
 * Portuguese clay tiles in courses for roof-plane mapping (u along the
 * eave, v up the slope): convex barrels, a proud lower lip per course,
 * burnt and pale tiles, lichen. 2 m tile.
 */
export function roofTiles({ S = 1024, seed = 53 } = {}) {
  const N = createNoise(seed);
  const N2 = createNoise(seed + 4);
  const cols = 9;
  const rows = 8;
  const img = shade(createImage(S), (p, u, v) => {
    const r = Math.min(rows - 1, Math.floor(v * rows));
    const lv = v * rows - r;
    const cu = u * cols + (r % 2) * 0.5;
    const c = ((Math.floor(cu) % cols) + cols) % cols;
    const lu = cu - Math.floor(cu);
    const id = hash2(c, r, seed);
    const id2 = hash2(c, r, seed + 1);
    // Slight per-tile skew so courses aren't machine perfect.
    const lu2 = clamp01(lu + (id2 - 0.5) * 0.06 * lv);
    const profile = Math.sin(Math.PI * lu2);
    const conv = Math.pow(profile, 0.6);
    const lip = smoothstep(0, 0.06, lv);
    const grain = N.fbm(u, v, 128, 2);
    p.h = 0.08 + lip * (0.32 * (1 - lv) + 0.5 * conv) + 0.03 * grain;
    let t = 0.72 + 0.26 * id;
    if (id2 < 0.12)
      t *= 0.68; // over-fired tile
    else if (id2 > 0.93) t *= 1.1; // replacement tile, paler
    t *= 0.72 + 0.28 * smoothstep(0, 0.2, profile);
    t *= 0.9 + 0.12 * N2.fbm(u, v, 16, 3);
    let r_ = t;
    let g_ = t * (0.84 + 0.08 * id2);
    let b_ = t * (0.78 + 0.1 * id);
    // Lichen rosettes: pale, rough, clustered.
    const cluster = smoothstep(0.55, 0.7, N.fbm(u, v, 6, 3));
    const spot = smoothstep(0.58, 0.68, N2.noise(u * 140, v * 140, 140));
    const lichen = cluster * spot;
    r_ = mix(r_, 0.95, lichen);
    g_ = mix(g_, 0.97, lichen);
    b_ = mix(b_, 0.86, lichen);
    p.r = r_;
    p.g = g_;
    p.b = b_;
    p.h += 0.03 * lichen;
    p.rough = 1.0 + 0.15 * lichen;
  });
  return bake(img, { tileSize: 2, depth: 0.05, cavityRadius: 5, cavityStrength: 1.3 });
}

/** Weathered vertical planks: grain, knots, end joints, open seams. 1.43 m tile. */
export function wood({ S = 512, seed = 71 } = {}) {
  const rnd = mulberry32(seed);
  const N = createNoise(seed);
  const N2 = createNoise(seed + 6);
  const planks = Array.from({ length: 6 }, () => ({
    tone: rnd(),
    freq: 10 + rnd() * 8,
    cut: rnd(),
    knots: Array.from({ length: Math.floor(rnd() * 2.5) }, () => ({
      u: 0.25 + rnd() * 0.5,
      v: rnd(),
      r: 0.02 + rnd() * 0.025,
    })),
  }));
  const img = shade(createImage(S), (p, u, v) => {
    const k = Math.min(5, Math.floor(u * 6));
    const pl = planks[k];
    const lu = u * 6 - k;
    const edge = Math.min(lu, 1 - lu) / 6;
    const seam = smoothstep(0.0008, 0.004, edge) * smoothstep(0.0008, 0.003, Math.abs(fract(v - pl.cut + 0.5) - 0.5));
    let arg = lu * pl.freq + N.fbm(u, v, 6, 3) * 3;
    let knotDark = 0;
    for (const kn of pl.knots) {
      let dv = v - kn.v;
      dv -= Math.round(dv);
      const d = Math.hypot((lu - kn.u) / 6, dv * 0.35);
      arg += 2.2 * Math.exp(-d / kn.r);
      knotDark = Math.max(knotDark, smoothstep(kn.r * 0.55, 0, d));
    }
    const rings = Math.sin(arg * TAU) * 0.5 + 0.5;
    const fiber = N2.fbm2(u, v, 160, 6, 2);
    p.h = seam * (0.55 + 0.14 * rings + 0.06 * fiber) - 0.1 * knotDark;
    let t = (0.74 + 0.22 * pl.tone) * (0.86 + 0.14 * rings) * (0.95 + 0.06 * fiber);
    t *= 1 - 0.45 * knotDark;
    t *= 0.55 + 0.45 * seam;
    setGrey(p, t, 0.04);
    p.rough = 1.05 + 0.05 * (1 - rings);
  });
  return bake(img, { tileSize: 1.43, depth: 0.006, cavityRadius: 2 });
}

/** Louvred shutter leaf (UV-mapped, u across ~0.45 m, v up ~1.6 m): frame, angled slats, chipped paint. */
export function shutter({ S = 512, seed = 83 } = {}) {
  const N = createNoise(seed);
  const N2 = createNoise(seed + 1);
  const img = shade(createImage(S), (p, u, v) => {
    const stile = u < 0.12 || u > 0.88;
    const rail = v < 0.045 || v > 0.955 || Math.abs(v - 0.5) < 0.022;
    const fiber = N2.fbm2(u, v, 64, 8, 2);
    let h;
    if (stile || rail) {
      const e = Math.min(
        Math.abs(u - 0.12),
        Math.abs(u - 0.88),
        Math.abs(v - 0.045),
        Math.abs(v - 0.955),
        Math.abs(Math.abs(v - 0.5) - 0.022),
      );
      h = 0.75 + 0.2 * smoothstep(0, 0.02, e);
    } else {
      const ph = fract((v - 0.045) * 30);
      h = 0.25 + 0.45 * ph * smoothstep(1, 0.9, ph);
    }
    h += 0.02 * fiber;
    const worn = stile || rail ? 1 : 0.6;
    const chip = smoothstep(0.66, 0.7, N.fbm(u, v, 12, 4)) * worn;
    p.h = h - 0.04 * chip;
    const t = 0.94 * (0.94 + 0.08 * fiber);
    p.r = mix(t, 0.62, chip);
    p.g = mix(t, 0.55, chip);
    p.b = mix(t, 0.48, chip);
    p.rough = mix(0.82, 1.15, chip);
  });
  return bake(img, { tileSize: 1, depth: 0.012, cavityRadius: 3, cavityStrength: 1.4 });
}

/** Four-panel fielded door (UV-mapped, u across ~1.15 m, v up ~2.3 m). */
export function door({ S = 512, seed = 89 } = {}) {
  const N = createNoise(seed);
  const panels = [
    [0.12, 0.47, 0.08, 0.42],
    [0.53, 0.88, 0.08, 0.42],
    [0.12, 0.47, 0.5, 0.92],
    [0.53, 0.88, 0.5, 0.92],
  ];
  const img = shade(createImage(S), (p, u, v) => {
    let h = 0.82;
    let vertical = true;
    for (const [u0, u1, v0, v1] of panels) {
      if (u < u0 || u > u1 || v < v0 || v > v1) continue;
      const inside = Math.min(u - u0, u1 - u, (v - v0) * 2, (v1 - v) * 2);
      const groove = smoothstep(0, 0.008, inside) * (1 - smoothstep(0.008, 0.014, inside));
      const field = smoothstep(0.012, 0.05, inside);
      h = 0.45 + 0.3 * field - 0.12 * groove;
    }
    if (v > 0.92 || v < 0.08 || (v > 0.42 && v < 0.5)) vertical = false;
    const fiber = vertical ? N.fbm2(u, v, 96, 8, 3) : N.fbm2(u, v, 8, 96, 3);
    const rings = Math.sin((vertical ? u * 40 : v * 20) * TAU + N.fbm(u, v, 6, 3) * 8) * 0.5 + 0.5;
    p.h = h + 0.03 * fiber;
    setGrey(p, (0.8 + 0.14 * rings) * (0.93 + 0.08 * fiber), 0.03);
    p.rough = 0.95;
  });
  return bake(img, { tileSize: 1.5, depth: 0.02, cavityRadius: 3, cavityStrength: 1.3 });
}

/**
 * Casement window (UV-mapped, u across ~0.9 m, v up ~1.6 m): painted frame,
 * glazing bars, glossy panes with interior hints. Variant 1 adds curtains.
 * Albedo is in colour (frame white, interior dark) — use a white material.
 */
export function windowPanes({ S = 512, seed = 97, curtains = false } = {}) {
  const N = createNoise(seed);
  const bars = (x, w) => x < w;
  const img = shade(createImage(S), (p, u, v) => {
    const outer = u < 0.06 || u > 0.94 || v < 0.035 || v > 0.965;
    const mullion = Math.abs(u - 0.5) < 0.022;
    const transom = Math.abs(v - 0.74) < 0.016;
    const leafU = u < 0.5 ? (u - 0.06) / 0.44 : (u - 0.5) / 0.44;
    const muntin = v < 0.74 && (bars(Math.abs(v - 0.27), 0.007) || bars(Math.abs(v - 0.505), 0.007));
    const muntinV = v > 0.74 && bars(Math.abs(leafU - 0.5), 0.012);
    const frame = outer || mullion || transom || muntin || muntinV;
    if (frame) {
      const fiber = N.fbm2(u, v, 32, 8, 2);
      p.h = outer ? 1 : mullion || transom ? 0.85 : 0.6;
      setGrey(p, 0.93 + 0.05 * fiber);
      p.rough = 1.0;
      return;
    }
    p.h = 0;
    // Interior: dark room, lighter towards the floor-to-ceiling depth falloff.
    const dark = 0.1 + 0.1 * smoothstep(0.95, 0.15, v) + 0.04 * N.fbm(u, v, 4, 2);
    let r = dark * 1.05;
    let g = dark;
    let b = dark * 1.1;
    if (curtains) {
      const side = Math.min(u, 1 - u);
      // Tied back: full width at the top, gathered towards the sill.
      const edge = 0.24 - 0.1 * smoothstep(0.55, 0.2, v);
      const cover = smoothstep(edge + 0.01, edge - 0.01, side) * smoothstep(0.04, 0.1, v);
      const folds = 0.78 + 0.22 * Math.sin((u * 70 + v * 3) * Math.PI);
      r = mix(r, 0.66 * folds, cover);
      g = mix(g, 0.58 * folds, cover);
      b = mix(b, 0.48 * folds, cover);
    }
    p.r = r;
    p.g = g;
    p.b = b;
    p.rough = 0.08 + 0.04 * N.fbm(u, v, 24, 2);
  });
  return bake(img, { tileSize: 1, depth: 0.03, cavityRadius: 3, cavityStrength: 1.2 });
}

/** Azulejos: 4×4 hand-painted cobalt tiles forming corner rosettes, glossy glaze, crazing. 0.56 m tile. */
export function azulejo({ S = 512, seed = 101 } = {}) {
  const N = createNoise(seed);
  const cells = createCells(seed, 22);
  const img = shade(createImage(S), (p, u, v) => {
    const tu = u * 4;
    const tv = v * 4;
    const lu = fract(tu);
    const lv = fract(tv);
    const e = Math.min(lu, 1 - lu, lv, 1 - lv);
    if (e < 0.012) {
      p.h = 0;
      setGrey(p, 0.84, 0.03);
      p.rough = 1.15;
      return;
    }
    const cr = cells(u, v);
    const craze = smoothstep(0.035, 0.0, cr.f2 - cr.f1);
    p.h = 0.6 + 0.35 * smoothstep(0.012, 0.06, e) - 0.04 * craze;
    // Corner rosette (shared by four tiles).
    const cu = lu < 0.5 ? lu : lu - 1;
    const cv = lv < 0.5 ? lv : lv - 1;
    const r = Math.hypot(cu, cv);
    const th = Math.atan2(cv, cu);
    const petal = r < 0.46 * (0.6 + 0.4 * Math.abs(Math.cos(4 * th))) && r > 0.1;
    const ring = Math.abs(r - 0.5) < 0.03;
    const border = e < 0.06 && e > 0.035;
    const heart = r < 0.085;
    // Centre motif: four-point star + dot.
    const x = lu - 0.5;
    const y = lv - 0.5;
    const star = Math.abs(x) + Math.abs(y) < 0.13 + 0.05 * Math.cos(4 * Math.atan2(y, x));
    const dot = Math.hypot(x, y) < 0.035;
    const brush = 0.82 + 0.18 * N.fbm(u, v, 48, 3);
    let col = [0.95, 0.95, 0.92];
    if (heart) col = [0.86, 0.64, 0.2];
    else if ((petal || ring || star || border) && !dot) col = [0.12 * brush, 0.25 * brush, 0.6 * brush + 0.05];
    const glaze = 1 - 0.18 * craze;
    p.r = col[0] * glaze;
    p.g = col[1] * glaze;
    p.b = col[2] * glaze;
    p.rough = 0.32 + 0.1 * craze + (col[0] < 0.5 ? 0.08 : 0);
  });
  return bake(img, { tileSize: 0.56, depth: 0.004, cavityRadius: 2 });
}

/** Painted cast iron: casting pits, flaking paint with rust. 1 m tile. */
export function castIron({ S = 256, seed = 109 } = {}) {
  const N = createNoise(seed);
  const N2 = createNoise(seed + 1);
  const img = shade(createImage(S), (p, u, v) => {
    const pits = smoothstep(0.75, 0.9, N2.noise(u * 64, v * 64, 64));
    const rust = smoothstep(0.62, 0.75, N.fbm(u, v, 8, 4));
    p.h = 0.6 + 0.1 * N.fbm(u, v, 32, 3) - 0.2 * pits - 0.08 * rust;
    p.r = mix(0.95, 1.0, rust);
    p.g = mix(0.95, 0.62, rust);
    p.b = mix(0.95, 0.42, rust);
    p.rough = mix(0.85, 1.3, rust);
  });
  return bake(img, { tileSize: 1, depth: 0.004, cavityRadius: 2 });
}

/** Olive bark: twisting vertical fissures and corky plates. 1 m tile. */
export function bark({ S = 512, seed = 113 } = {}) {
  const N = createNoise(seed);
  const N2 = createNoise(seed + 2);
  const img = shade(createImage(S), (p, u, v) => {
    const warp = N.fbm(u, v, 4, 4) * 2.5;
    const ridge = 1 - Math.abs(Math.sin((u * 9 + warp) * Math.PI));
    const plates = N2.fbm2(u, v, 18, 6, 3);
    const fissure = smoothstep(0.75, 0.98, ridge);
    p.h = 0.7 - 0.6 * fissure + 0.15 * plates;
    const t = (0.78 + 0.2 * plates) * (1 - 0.55 * fissure);
    setGrey(p, t, 0.03);
    p.rough = 1.1;
  });
  return bake(img, { tileSize: 1, depth: 0.03, cavityRadius: 4, cavityStrength: 1.4 });
}

/** Foliage clumps: overlapping leaf cells with per-leaf tone. 1 m tile. */
export function leaves({ S = 256, seed = 127 } = {}) {
  const cells = createCells(seed, 18);
  const img = shade(createImage(S), (p, u, v) => {
    const c = cells(u, v);
    const leaf = 1 - smoothstep(0.1, 0.62, c.f1);
    const vein = smoothstep(0.04, 0, Math.abs((u - c.cx) * 0.7 - (v - c.cy) * 0.7) * 18);
    p.h = leaf * 0.9 - 0.08 * vein * leaf;
    const t = (0.74 + 0.3 * c.id) * (0.55 + 0.45 * leaf);
    p.r = t * (0.92 + 0.12 * c.id);
    p.g = t;
    p.b = t * 0.85;
    p.rough = 0.85;
  });
  return bake(img, { tileSize: 1, depth: 0.05, cavityRadius: 3, cavityStrength: 1.3 });
}

/** Plain-weave fabric for UV-mapped cloth (banners, towels, parasols, seats). */
export function weave({ S = 256, threads = 32 } = {}) {
  const N = createNoise(7);
  const img = shade(createImage(S), (p, u, v) => {
    const i = Math.floor(u * threads);
    const j = Math.floor(v * threads);
    const lu = fract(u * threads);
    const lv = fract(v * threads);
    const warpTop = (i + j) % 2 === 0;
    const warp = Math.sin(Math.PI * lu) * (warpTop ? 1 : 0.55);
    const weft = Math.sin(Math.PI * lv) * (warpTop ? 0.55 : 1);
    const slub = N.fbm(u, v, 16, 2);
    p.h = Math.max(warp, weft) * (0.85 + 0.3 * slub);
    setGrey(p, 0.9 + 0.1 * p.h);
    p.rough = 1.1;
  });
  return bake(img, { tileSize: 0.08, depth: 0.0006, cavityRadius: 1 });
}

/** Tyre tread (UV: u around the wheel, v across the tread): zig-zag grooves and sipes. */
export function tread({ S = 256 } = {}) {
  const img = shade(createImage(S), (p, u, v) => {
    const block = fract(u * 24);
    const zig = Math.abs(fract(u * 24) - 0.5) * 0.12;
    const centre = Math.abs(v - 0.5 - zig + 0.03) < 0.035;
    const outer = Math.abs(Math.abs(v - 0.5) - 0.3) < 0.025;
    const sipe = block < 0.12 && Math.abs(v - 0.5) > 0.06 && Math.abs(v - 0.5) < 0.42;
    const shoulder = Math.abs(v - 0.5) > 0.44;
    p.h = centre || outer ? 0.1 : sipe ? 0.35 : shoulder ? 0.6 : 1;
    setGrey(p, centre || outer || sipe ? 0.7 : 1);
    p.rough = 1.05;
  });
  return bake(img, { tileSize: 0.3, depth: 0.008, cavityRadius: 2 });
}

/** Pebbled leather (seats, boots). */
export function leather({ S = 256, seed = 131 } = {}) {
  const cells = createCells(seed, 26);
  const N = createNoise(seed);
  const img = shade(createImage(S), (p, u, v) => {
    const c = cells(u, v);
    const crease = smoothstep(0.0, 0.12, c.f2 - c.f1);
    p.h = 0.4 + 0.5 * crease + 0.1 * N.fbm(u, v, 8, 3);
    setGrey(p, 0.86 + 0.14 * crease * (0.8 + 0.2 * c.id));
    p.rough = 0.75 + 0.25 * (1 - crease);
  });
  return bake(img, { tileSize: 0.3, depth: 0.0015, cavityRadius: 1 });
}

/** Thrown terracotta: wheel rings, pores, pale efflorescence blooms. 0.5 m tile (rings run along u). */
export function terracotta({ S = 256, seed = 137 } = {}) {
  const N = createNoise(seed);
  const cells = createCells(seed, 30);
  const img = shade(createImage(S), (p, u, v) => {
    const rings = Math.sin((v * 34 + N.fbm(u, v, 4, 2) * 1.5) * TAU) * 0.5 + 0.5;
    const pore = smoothstep(0.12, 0.0, cells(u, v).f1);
    const bloom = smoothstep(0.6, 0.78, N.fbm(u, v, 5, 4));
    p.h = 0.5 + 0.12 * rings - 0.25 * pore;
    const t = (0.86 + 0.1 * N.fbm(u, v, 24, 3)) * (1 - 0.25 * pore);
    p.r = mix(t, 1.0, bloom * 0.6);
    p.g = mix(t, 1.0, bloom * 0.7);
    p.b = mix(t, 0.98, bloom * 0.75);
    p.rough = 1.0 + 0.15 * bloom;
  });
  return bake(img, { tileSize: 0.5, depth: 0.002, cavityRadius: 2 });
}

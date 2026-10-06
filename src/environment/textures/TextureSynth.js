/**
 * Texture synthesis core — pure JS on typed arrays (no DOM, runs in Node).
 *
 * Every procedural material is authored as a small set of *fields* over the
 * unit tile [0,1)²: a height field, an albedo (RGB) and a roughness factor.
 * `bake()` derives the rest physically from the height:
 *
 *   normal   central differences of the height, scaled by the real relief
 *            depth (m) over the texel size (m) — so a 3 cm mortar joint reads
 *            the same on a 2 m tile as on a 3 m one
 *   cavity   height minus its local blur → baked micro-occlusion in joints,
 *            cracks and grain (darkens albedo / indirect light in the shader)
 *
 * Output is two RGBA8 buffers: albedo (sRGB) and a packed "detail" map
 * (RG = tangent-space normal XY, B = roughness factor / 2, A = cavity).
 * All noise is periodic, so every texture tiles seamlessly.
 *
 * Texture-space convention: x → u (right), y → v (up); row 0 is v ≈ 0.
 * (DataTextures are uploaded without a Y flip.)
 */

export function mulberry32(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Integer lattice hash → [0, 1). */
export function hash2(ix, iy, seed) {
  let h = (Math.imul(ix, 374761393) + Math.imul(iy, 668265263) + Math.imul(seed, 1442695041)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

const mod = (a, n) => ((a % n) + n) % n;
export const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
export const smoothstep = (e0, e1, x) => {
  const t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
};
export const mix = (a, b, t) => a + (b - a) * t;

/**
 * Periodic value noise + fBm. Coordinates are in tile units (u, v ∈ [0,1));
 * `freq` must be an integer so the lattice wraps exactly at the tile edge.
 */
export function createNoise(seed = 1) {
  // Lattice values are cached per period (px × py table), so a noise sample
  // is four array reads + a quintic blend — no hashing in the inner loop.
  const square = []; // period → table (the common isotropic case, array-indexed)
  const tables = new Map(); // anisotropic periods
  const build = (px, py) => {
    const t = new Float32Array(px * py);
    for (let y = 0; y < py; y++) for (let x = 0; x < px; x++) t[y * px + x] = hash2(x, y, seed);
    return t;
  };
  const table = (px, py) => {
    if (px === py) return square[px] ?? (square[px] = build(px, py));
    const key = px * 65536 + py;
    let t = tables.get(key);
    if (!t) tables.set(key, (t = build(px, py)));
    return t;
  };
  const noise2 = (x, y, px, py) => {
    const t = table(px, py);
    let x0 = Math.floor(x);
    let y0 = Math.floor(y);
    const fx = x - x0;
    const fy = y - y0;
    if (x0 < 0 || x0 >= px) x0 = mod(x0, px);
    if (y0 < 0 || y0 >= py) y0 = mod(y0, py);
    const x1 = x0 + 1 === px ? 0 : x0 + 1;
    const r0 = y0 * px;
    const r1 = (y0 + 1 === py ? 0 : y0 + 1) * px;
    const ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10);
    const uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10);
    const a = t[r0 + x0];
    const b = t[r0 + x1];
    const c = t[r1 + x0];
    const d = t[r1 + x1];
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
  };
  const noise = (x, y, period) => noise2(x, y, period, period);
  /** Isotropic fBm in [0,1]. */
  const fbm = (u, v, freq, octaves = 4, gain = 0.5) => {
    let sum = 0;
    let amp = 1;
    let norm = 0;
    let f = freq;
    for (let o = 0; o < octaves; o++) {
      sum += amp * noise2(u * f, v * f, f, f);
      norm += amp;
      amp *= gain;
      f *= 2;
    }
    return sum / norm;
  };
  /** Anisotropic fBm with independent (integer) periods per axis. */
  const fbm2 = (u, v, fx, fy, octaves = 4, gain = 0.5) => {
    let sum = 0;
    let amp = 1;
    let norm = 0;
    for (let o = 0; o < octaves; o++) {
      sum += amp * noise2(u * fx, v * fy, fx, fy);
      norm += amp;
      amp *= gain;
      fx *= 2;
      fy *= 2;
    }
    return sum / norm;
  };
  return { noise, fbm, fbm2, noise2 };
}

/**
 * Periodic cellular (Worley) noise on an n×n jittered grid.
 * Returns F1, F2 (in cell units) and the id/hash of the nearest cell.
 */
export function createCells(seed = 1, n = 8) {
  const out = { f1: 0, f2: 0, id: 0, cx: 0, cy: 0 };
  return (u, v) => {
    const x = u * n;
    const y = v * n;
    const xi = Math.floor(x);
    const yi = Math.floor(y);
    let f1 = 9;
    let f2 = 9;
    let id = 0;
    let bx = 0;
    let by = 0;
    for (let j = -1; j <= 1; j++)
      for (let i = -1; i <= 1; i++) {
        const cx = xi + i;
        const cy = yi + j;
        const wx = mod(cx, n);
        const wy = mod(cy, n);
        const px = cx + hash2(wx, wy, seed);
        const py = cy + hash2(wx, wy, seed + 17);
        const d = Math.hypot(px - x, py - y);
        if (d < f1) {
          f2 = f1;
          f1 = d;
          id = hash2(wx, wy, seed + 31);
          bx = px;
          by = py;
        } else if (d < f2) f2 = d;
      }
    out.f1 = f1;
    out.f2 = f2;
    out.id = id;
    out.cx = bx / n;
    out.cy = by / n;
    return out;
  };
}

/** Fields of one texture: height [0,1], albedo RGB [0,1] (display space), roughness factor. */
export function createImage(S) {
  return {
    S,
    height: new Float32Array(S * S),
    albedo: new Float32Array(S * S * 3),
    rough: new Float32Array(S * S).fill(1),
  };
}

/**
 * Runs `fn(u, v, x, y, i)` for every texel (u, v at texel centres) and stores
 * the returned values from the shared `px` record.
 */
export function shade(img, fn) {
  const { S, height, albedo, rough } = img;
  const px = { h: 0, r: 1, g: 1, b: 1, rough: 1 };
  for (let y = 0; y < S; y++) {
    const v = (y + 0.5) / S;
    for (let x = 0; x < S; x++) {
      const u = (x + 0.5) / S;
      const i = y * S + x;
      px.h = 0;
      px.r = px.g = px.b = 1;
      px.rough = 1;
      fn(px, u, v, x, y, i);
      height[i] = px.h;
      albedo[i * 3] = px.r;
      albedo[i * 3 + 1] = px.g;
      albedo[i * 3 + 2] = px.b;
      rough[i] = px.rough;
    }
  }
  return img;
}

/** Separable box blur with wrap-around (for cavity). */
function blurWrap(src, S, radius) {
  const tmp = new Float32Array(S * S);
  const dst = new Float32Array(S * S);
  const w = 2 * radius + 1;
  for (let y = 0; y < S; y++) {
    let acc = 0;
    for (let k = -radius; k <= radius; k++) acc += src[y * S + mod(k, S)];
    for (let x = 0; x < S; x++) {
      tmp[y * S + x] = acc / w;
      acc += src[y * S + mod(x + radius + 1, S)] - src[y * S + mod(x - radius, S)];
    }
  }
  for (let x = 0; x < S; x++) {
    let acc = 0;
    for (let k = -radius; k <= radius; k++) acc += tmp[mod(k, S) * S + x];
    for (let y = 0; y < S; y++) {
      dst[y * S + x] = acc / w;
      acc += tmp[mod(y + radius + 1, S) * S + x] - tmp[mod(y - radius, S) * S + x];
    }
  }
  return dst;
}

/**
 * Bakes the fields into GPU-ready RGBA8 buffers.
 * @param {object} img fields from createImage/shade
 * @param {object} o
 * @param {number} o.tileSize metres covered by one tile
 * @param {number} o.depth metres of relief for height 0 → 1
 * @param {number} [o.cavityRadius] texels
 * @param {number} [o.cavityStrength]
 */
export function bake(img, { tileSize, depth, cavityRadius = 3, cavityStrength = 1 }) {
  const { S, height, albedo, rough } = img;
  const albedoBytes = new Uint8Array(S * S * 4);
  const detailBytes = new Uint8Array(S * S * 4);
  const k = depth / (tileSize / S); // slope per unit height difference per texel
  const blur = blurWrap(height, S, cavityRadius);
  for (let y = 0; y < S; y++) {
    const yu = ((y + 1) % S) * S;
    const yd = ((y - 1 + S) % S) * S;
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      const xr = y * S + ((x + 1) % S);
      const xl = y * S + ((x - 1 + S) % S);
      const dhdu = (height[xr] - height[xl]) * 0.5 * k;
      const dhdv = (height[yu + x] - height[yd + x]) * 0.5 * k;
      const inv = 1 / Math.sqrt(dhdu * dhdu + dhdv * dhdv + 1);
      const nx = -dhdu * inv;
      const ny = -dhdv * inv;
      const cav = clamp01(1 + (height[i] - blur[i]) * 4 * cavityStrength);
      const o = i * 4;
      detailBytes[o] = (nx * 127.5 + 128) | 0;
      detailBytes[o + 1] = (ny * 127.5 + 128) | 0;
      detailBytes[o + 2] = (clamp01(rough[i] * 0.5) * 255 + 0.5) | 0;
      detailBytes[o + 3] = (cav * 255 + 0.5) | 0;
      albedoBytes[o] = (clamp01(albedo[i * 3]) * 255 + 0.5) | 0;
      albedoBytes[o + 1] = (clamp01(albedo[i * 3 + 1]) * 255 + 0.5) | 0;
      albedoBytes[o + 2] = (clamp01(albedo[i * 3 + 2]) * 255 + 0.5) | 0;
      albedoBytes[o + 3] = 255;
    }
  }
  return { S, albedo: albedoBytes, detail: detailBytes };
}

// -----------------------------------------------------------------------------
// Layout helpers
// -----------------------------------------------------------------------------

/**
 * Running-bond courses: `rows` courses, each split into blocks whose widths
 * sum to exactly 1 (seamless), shifted by a random per-row offset.
 * Returns a lookup (u, v) → block record (local coords in tile units).
 */
export function runningBond(rnd, rows, { minBlocks = 2, maxBlocks = 4, irregular = 0.6 } = {}) {
  const courses = [];
  for (let r = 0; r < rows; r++) {
    const n = minBlocks + Math.floor(rnd() * (maxBlocks - minBlocks + 1));
    const widths = Array.from({ length: n }, () => 1 - irregular / 2 + rnd() * irregular);
    const sum = widths.reduce((a, b) => a + b, 0);
    let x = 0;
    const blocks = widths.map((w) => {
      const b = { u0: x, u1: x + w / sum, tone: rnd(), seed: rnd(), angle: rnd() * Math.PI, hue: rnd() };
      x = b.u1;
      return b;
    });
    courses.push({ shift: rnd(), blocks });
  }
  const rowH = 1 / rows;
  const rec = { block: null, row: 0, px: 0, py: 0, halfW: 0, halfH: rowH / 2 };
  return (u, v) => {
    const r = Math.min(rows - 1, Math.floor(v * rows));
    const c = courses[r];
    let ru = u + c.shift;
    ru -= Math.floor(ru);
    let b = c.blocks[c.blocks.length - 1];
    for (const blk of c.blocks)
      if (ru < blk.u1) {
        b = blk;
        break;
      }
    rec.block = b;
    rec.row = r;
    rec.halfW = (b.u1 - b.u0) / 2;
    rec.px = ru - (b.u0 + b.u1) / 2;
    rec.py = v - (r + 0.5) * rowH;
    return rec;
  };
}

/** Signed distance to a rounded rectangle (negative inside). */
export function roundedRectSDF(px, py, halfW, halfH, radius) {
  const qx = Math.abs(px) - (halfW - radius);
  const qy = Math.abs(py) - (halfH - radius);
  const ox = Math.max(qx, 0);
  const oy = Math.max(qy, 0);
  return Math.hypot(ox, oy) + Math.min(Math.max(qx, qy), 0) - radius;
}

/** Stamps random-walk cracks into a mask (with wrap). Returns Float32Array mask [0,1]. */
export function crackMask(S, rnd, count, { length = 0.25, width = 1.2, wander = 0.6 } = {}) {
  const mask = new Float32Array(S * S);
  const stamp = (cx, cy, r) => {
    const R = Math.ceil(r + 1);
    for (let dy = -R; dy <= R; dy++)
      for (let dx = -R; dx <= R; dx++) {
        const d = Math.hypot(dx, dy);
        if (d > r + 1) continue;
        const x = mod(Math.round(cx) + dx, S);
        const y = mod(Math.round(cy) + dy, S);
        const a = clamp01(r + 0.5 - d);
        const i = y * S + x;
        if (a > mask[i]) mask[i] = a;
      }
  };
  for (let c = 0; c < count; c++) {
    let x = rnd() * S;
    let y = rnd() * S;
    let ang = rnd() * Math.PI * 2;
    const steps = Math.round((length * S * (0.5 + rnd())) / 2);
    for (let s = 0; s < steps; s++) {
      const r = width * (1 - s / steps) * (0.6 + rnd() * 0.6);
      stamp(x, y, Math.max(0.35, r));
      ang += (rnd() - 0.5) * wander;
      x += Math.cos(ang) * 2;
      y += Math.sin(ang) * 2;
      if (rnd() < 0.02) {
        // Branch.
        const bx = x;
        const by = y;
        let ba = ang + (rnd() < 0.5 ? 1 : -1) * (0.6 + rnd() * 0.6);
        for (let t = 0; t < steps / 4; t++) {
          stamp(bx + Math.cos(ba) * 2 * t, by + Math.sin(ba) * 2 * t, Math.max(0.3, r * 0.6));
          ba += (rnd() - 0.5) * wander;
        }
      }
    }
  }
  return mask;
}

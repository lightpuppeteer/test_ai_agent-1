import * as THREE from 'three';

import * as Patterns from './textures/Patterns.js';

/**
 * Texture sets for the whole world, generated procedurally at startup — no
 * asset downloads, one consistent art direction.
 *
 * Synthesised sets (stone, stucco, setts, slabs, roof tiles, wood, shutters,
 * doors, windows, azulejos, iron, bark, leaves, fabric, tread, leather) come
 * from textures/Patterns.js as an albedo map plus a packed detail map
 * (normal XY, roughness factor, cavity) consumed by StylizedMaterial.
 *
 * Generation runs in a small pool of Web Workers. `set(name)` returns
 * full-size textures *immediately* (flat placeholders: white albedo, neutral
 * detail) and fills them in place when the worker delivers, so building the
 * world never waits on several seconds of per-pixel work. `ready` resolves
 * when every requested set has arrived. Without Worker support (Node) sets
 * are generated synchronously.
 *
 * Banners and towels are painted on a 2D canvas (UV-mapped colour designs).
 */

/** name → [Patterns function, options] */
const SETS = {
  ashlar: ['ashlar'],
  stucco: ['stucco'],
  cobbles: ['setts'],
  paving: ['paving'],
  roofTiles: ['roofTiles'],
  wood: ['wood'],
  shutter: ['shutter'],
  door: ['door'],
  window: ['windowPanes'],
  windowCurtains: ['windowPanes', { curtains: true, seed: 98 }],
  azulejo: ['azulejo'],
  castIron: ['castIron'],
  bark: ['bark'],
  leaves: ['leaves'],
  weave: ['weave'],
  tread: ['tread'],
  leather: ['leather'],
  terracotta: ['terracotta'],
};
/** Edge length per set (must match the Patterns defaults). */
const SIZES = {
  ashlar: 1024,
  stucco: 1024,
  cobbles: 1024,
  paving: 1024,
  roofTiles: 1024,
  castIron: 256,
  leaves: 256,
  weave: 256,
  tread: 256,
  leather: 256,
  terracotta: 256,
};

class WorkerPool {
  constructor(size) {
    this.size = size;
    this.workers = [];
    this.idle = [];
    this.queue = [];
    this.jobs = new Map();
    this.nextId = 1;
    this.reaper = 0;
  }

  run(fn, options) {
    return new Promise((resolve, reject) => {
      this.queue.push({ id: this.nextId++, fn, options, resolve, reject });
      this._pump();
    });
  }

  _spawn() {
    const w = new Worker(new URL('./textures/texture.worker.js', import.meta.url), { type: 'module' });
    w.onmessage = ({ data }) => {
      const job = this.jobs.get(data.id);
      this.jobs.delete(data.id);
      this.idle.push(w);
      this._pump();
      if (data.error) job.reject(new Error(data.error));
      else job.resolve(data);
    };
    this.workers.push(w);
    this.idle.push(w);
  }

  _pump() {
    clearTimeout(this.reaper);
    while (this.queue.length && !this.idle.length && this.workers.length < this.size) this._spawn();
    while (this.idle.length && this.queue.length) {
      const job = this.queue.shift();
      this.jobs.set(job.id, job);
      this.idle.pop().postMessage({ id: job.id, fn: job.fn, options: job.options });
    }
    // Free the workers once nothing has been requested for a while.
    if (!this.jobs.size) this.reaper = setTimeout(() => this.dispose(), 3000);
  }

  dispose() {
    for (const w of this.workers) w.terminate();
    this.workers.length = 0;
    this.idle.length = 0;
  }
}

function dataTexture(S, fill, srgb, anisotropy) {
  const data = new Uint8Array(S * S * 4);
  new Uint32Array(data.buffer).fill(fill);
  const t = new THREE.DataTexture(data, S, S, THREE.RGBAFormat, THREE.UnsignedByteType);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  t.generateMipmaps = true;
  t.minFilter = THREE.LinearMipmapLinearFilter;
  t.magFilter = THREE.LinearFilter;
  t.anisotropy = anisotropy;
  t.needsUpdate = true;
  return t;
}

// Little-endian RGBA words: white albedo, neutral detail (flat normal, roughness ×1, no cavity).
const WHITE = 0xffffffff;
const NEUTRAL = 0xff808080;

function mulberry32(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function canvas(size) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  return [c, c.getContext('2d')];
}

const tint = (r, g, b, a = 1) => `rgba(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)},${a})`;

/** Draws `fn(dx, dy)` at the 9 wrap offsets so shapes tile seamlessly. */
function wrapped(size, fn) {
  for (let ox = -1; ox <= 1; ox++) for (let oy = -1; oy <= 1; oy++) fn(ox * size, oy * size);
}

/** Soft brush-like blotches — the base of the painterly look. */
function blotches(ctx, size, rnd, count, rMin, rMax, vMin, vMax, alpha) {
  for (let i = 0; i < count; i++) {
    const x = rnd() * size;
    const y = rnd() * size;
    const r = rMin + rnd() * (rMax - rMin);
    const v = vMin + rnd() * (vMax - vMin);
    const warm = rnd() * 0.04;
    wrapped(size, (dx, dy) => {
      const g = ctx.createRadialGradient(x + dx, y + dy, 0, x + dx, y + dy, r);
      g.addColorStop(0, tint(v + warm, v, v - warm, alpha));
      g.addColorStop(1, tint(v + warm, v, v - warm, 0));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.ellipse(x + dx, y + dy, r, r * (0.55 + rnd() * 0.5), rnd() * Math.PI, 0, Math.PI * 2);
      ctx.fill();
    });
  }
}

function finish(c, anisotropy) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = anisotropy;
  t.generateMipmaps = true;
  t.minFilter = THREE.LinearMipmapLinearFilter;
  t.needsUpdate = true;
  return t;
}

export class TextureFactory {
  constructor(renderer) {
    this.anisotropy = Math.min(8, renderer?.capabilities.getMaxAnisotropy() ?? 1);
    this.cache = new Map();
    this.sets = new Map();
    this.pending = [];
    const cores = globalThis.navigator?.hardwareConcurrency ?? 2;
    this.pool = typeof Worker !== 'undefined' ? new WorkerPool(Math.max(1, Math.min(4, cores - 1))) : null;
  }

  /** Resolves once every texture set requested so far has been generated. */
  get ready() {
    return Promise.all(this.pending);
  }

  /**
   * Texture set { map, detail } by name (see SETS). Returned textures are
   * usable immediately and upgrade in place when generation finishes.
   */
  set(name) {
    let set = this.sets.get(name);
    if (set) return set;
    const [fn, options] = SETS[name] ?? [];
    if (!fn) throw new Error(`Unknown texture set "${name}"`);
    const S = SIZES[name] ?? 512;
    set = {
      map: dataTexture(S, WHITE, true, this.anisotropy),
      detail: dataTexture(S, NEUTRAL, false, this.anisotropy),
    };
    set.map.name = `${name}.albedo`;
    set.detail.name = `${name}.detail`;
    this.sets.set(name, set);
    const apply = (r) => {
      set.map.image.data = r.albedo;
      set.detail.image.data = r.detail;
      set.map.needsUpdate = set.detail.needsUpdate = true;
    };
    if (this.pool) this.pending.push(this.pool.run(fn, options).then(apply));
    else apply(Patterns[fn](options));
    return set;
  }

  /** Albedo map of a set (or a cached painted texture). */
  get(name) {
    if (SETS[name]) return this.set(name).map;
    if (!this.cache.has(name)) this.cache.set(name, this[name]());
    return this.cache.get(name);
  }

  /**
   * Heraldic banner (UV mapped). Designs: 0 crimson/gold with a tower,
   * 1 azure/white quartered, 2 gold/red pales. Painted with soft edges.
   */
  banner(design = 0) {
    const W = 128;
    const H = 256;
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const ctx = c.getContext('2d');
    const rnd = mulberry32(91 + design * 7);
    if (design === 0) {
      ctx.fillStyle = '#9e2a2b';
      ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = '#e0b445';
      ctx.fillRect(10, 10, W - 20, 8);
      ctx.fillRect(10, H - 40, W - 20, 8);
      // Stylised tower.
      ctx.fillRect(44, 70, 40, 90);
      for (let i = 0; i < 3; i++) ctx.fillRect(44 + i * 15, 58, 10, 14);
      ctx.fillStyle = '#9e2a2b';
      ctx.fillRect(58, 128, 12, 32);
    } else if (design === 1) {
      const colors = ['#2f5d8c', '#efe8d8'];
      for (let i = 0; i < 4; i++) {
        ctx.fillStyle = colors[(i + Math.floor(i / 2)) % 2];
        ctx.fillRect((i % 2) * (W / 2), Math.floor(i / 2) * (H / 2 - 20), W / 2, H / 2 - 20);
      }
      ctx.fillStyle = '#2f5d8c';
      ctx.fillRect(0, H - 40, W, 40);
    } else {
      for (let i = 0; i < 5; i++) {
        ctx.fillStyle = i % 2 ? '#b23a2e' : '#e3b54c';
        ctx.fillRect((i * W) / 5, 0, W / 5 + 1, H);
      }
    }
    // Swallow-tail cut at the bottom (alpha) + weathering.
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.moveTo(0, H);
    ctx.lineTo(W / 2, H - 34);
    ctx.lineTo(W, H);
    ctx.closePath();
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
    blotches(ctx, W, rnd, 20, 10, 40, 0.75, 1.0, 0.12);
    const t = finish(c, this.anisotropy);
    t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
    return t;
  }

  /** Striped beach towel (UV mapped, not triplanar). */
  towel(colorA = '#d9534f', colorB = '#f4eadc') {
    const S = 128;
    const [c, ctx] = canvas(S);
    const stripes = 7;
    for (let i = 0; i < stripes; i++) {
      ctx.fillStyle = i % 2 ? colorB : colorA;
      ctx.fillRect(0, (i * S) / stripes, S, S / stripes);
    }
    const rnd = mulberry32(colorA.length * 13);
    blotches(ctx, S, rnd, 25, 5, 20, 0.85, 1.0, 0.15);
    const t = finish(c, this.anisotropy);
    t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
    return t;
  }
}

import * as THREE from 'three';

/**
 * Procedural, tileable, low-frequency "painted" textures generated on a 2D
 * canvas at startup — no asset downloads, consistent art direction.
 *
 * Textures are authored *near white* with darker detail; the material colour
 * (from PALETTE) supplies the hue, so one granite texture serves both light
 * and dark stone, etc. All are meant for world-space triplanar mapping.
 */

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

const grey = (v, a = 1) => `rgba(${Math.round(v * 255)},${Math.round(v * 255)},${Math.round(v * 255)},${a})`;
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

function speckle(ctx, size, rnd, count, vMin, vMax, alpha) {
  for (let i = 0; i < count; i++) {
    ctx.fillStyle = grey(vMin + rnd() * (vMax - vMin), alpha);
    const s = 1 + rnd() * 2;
    ctx.fillRect(rnd() * size, rnd() * size, s, s);
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
    this.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
    this.cache = new Map();
  }

  get(name) {
    if (!this.cache.has(name)) this.cache.set(name, this[name]());
    return this.cache.get(name);
  }

  /** Granite ashlar: staggered blocks, soft mortar, per-block tone. 2 m tile. */
  ashlar() {
    const S = 512;
    const [c, ctx] = canvas(S);
    const rnd = mulberry32(11);
    ctx.fillStyle = grey(0.62);
    ctx.fillRect(0, 0, S, S);
    const rows = 6;
    const rh = S / rows;
    for (let r = 0; r < rows; r++) {
      let x = -rnd() * 80;
      while (x < S) {
        const w = 70 + rnd() * 110;
        const v = 0.84 + rnd() * 0.14;
        const draw = (dx) => {
          ctx.fillStyle = grey(v);
          ctx.beginPath();
          ctx.roundRect(x + dx + 3, r * rh + 3, w - 6, rh - 6, 9);
          ctx.fill();
        };
        draw(0);
        draw(S);
        draw(-S);
        x += w;
      }
    }
    blotches(ctx, S, rnd, 60, 20, 90, 0.75, 1.0, 0.18);
    speckle(ctx, S, rnd, 5000, 0.45, 1.0, 0.35);
    return finish(c, this.anisotropy);
  }

  /** Lime-washed stucco: near-white with soft weathering and faint drips. 3 m tile. */
  stucco() {
    const S = 512;
    const [c, ctx] = canvas(S);
    const rnd = mulberry32(23);
    ctx.fillStyle = grey(0.97);
    ctx.fillRect(0, 0, S, S);
    blotches(ctx, S, rnd, 90, 30, 140, 0.86, 1.0, 0.22);
    // Weathering streaks.
    for (let i = 0; i < 26; i++) {
      const x = rnd() * S;
      const y = rnd() * S;
      const len = 60 + rnd() * 200;
      wrapped(S, (dx, dy) => {
        const g = ctx.createLinearGradient(0, y + dy, 0, y + dy + len);
        g.addColorStop(0, grey(0.8, 0.0));
        g.addColorStop(0.3, grey(0.8, 0.12));
        g.addColorStop(1, grey(0.8, 0.0));
        ctx.fillStyle = g;
        ctx.fillRect(x + dx, y + dy, 3 + rnd() * 8, len);
      });
    }
    speckle(ctx, S, rnd, 1500, 0.8, 1.0, 0.25);
    return finish(c, this.anisotropy);
  }

  /** Granite setts (paralelepípedos): staggered rounded blocks, soft joints. 2 m tile. */
  cobbles() {
    const S = 512;
    const [c, ctx] = canvas(S);
    const rnd = mulberry32(37);
    ctx.fillStyle = grey(0.6);
    ctx.fillRect(0, 0, S, S);
    const rows = 11;
    const rh = S / rows;
    for (let r = 0; r < rows; r++) {
      let x = -rnd() * 40;
      while (x < S) {
        const w = rh * (0.9 + rnd() * 0.7);
        const v = 0.8 + rnd() * 0.18;
        const jy = (rnd() - 0.5) * 3;
        const rot = (rnd() - 0.5) * 0.06;
        const cx = x + w / 2;
        const cy = r * rh + rh / 2 + jy;
        wrapped(S, (dx, dy) => {
          ctx.save();
          ctx.translate(cx + dx, cy + dy);
          ctx.rotate(rot);
          const g = ctx.createLinearGradient(-w / 2, -rh / 2, w / 2, rh / 2);
          g.addColorStop(0, grey(Math.min(1, v + 0.05)));
          g.addColorStop(1, grey(v * 0.9));
          ctx.fillStyle = g;
          ctx.beginPath();
          ctx.roundRect(-w / 2 + 2.5, -rh / 2 + 2.5, w - 5, rh - 5, 10);
          ctx.fill();
          ctx.restore();
        });
        x += w;
      }
    }
    blotches(ctx, S, rnd, 50, 20, 90, 0.75, 1.0, 0.16);
    speckle(ctx, S, rnd, 3500, 0.45, 1.0, 0.25);
    return finish(c, this.anisotropy);
  }

  /** Portuguese clay roof tiles (telha): scalloped rows with tone variation. 2 m tile. */
  roofTiles() {
    const S = 512;
    const [c, ctx] = canvas(S);
    const rnd = mulberry32(53);
    ctx.fillStyle = grey(0.55);
    ctx.fillRect(0, 0, S, S);
    const cols = 10;
    const rows = 12;
    const w = S / cols;
    const h = S / rows;
    for (let r = rows; r >= -1; r--) {
      for (let i = -1; i <= cols; i++) {
        const x = (i + (r % 2) * 0.5) * w;
        const y = r * h;
        const v = 0.78 + rnd() * 0.22;
        const g = ctx.createLinearGradient(x, 0, x + w, 0);
        g.addColorStop(0, grey(v * 0.75));
        g.addColorStop(0.45, grey(v));
        g.addColorStop(1, grey(v * 0.7));
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.moveTo(x + 2, y);
        ctx.lineTo(x + 2, y + h * 1.25);
        ctx.quadraticCurveTo(x + w / 2, y + h * 1.65, x + w - 2, y + h * 1.25);
        ctx.lineTo(x + w - 2, y);
        ctx.closePath();
        ctx.fill();
      }
    }
    blotches(ctx, S, rnd, 40, 20, 80, 0.6, 1.0, 0.15);
    return finish(c, this.anisotropy);
  }

  /** Weathered planks for benches, tables, doors, boats. 1.5 m tile. */
  wood() {
    const S = 256;
    const [c, ctx] = canvas(S);
    const rnd = mulberry32(71);
    const planks = 5;
    const pw = S / planks;
    for (let i = 0; i < planks; i++) {
      const v = 0.78 + rnd() * 0.2;
      ctx.fillStyle = grey(v);
      ctx.fillRect(i * pw, 0, pw, S);
      for (let k = 0; k < 9; k++) {
        ctx.strokeStyle = grey(v * (0.75 + rnd() * 0.15), 0.5);
        ctx.lineWidth = 1 + rnd() * 1.5;
        ctx.beginPath();
        const x0 = i * pw + rnd() * pw;
        const amp = 2 + rnd() * 4;
        const f = 0.02 + rnd() * 0.03;
        for (let y = 0; y <= S; y += 8) ctx.lineTo(x0 + Math.sin((y * f * Math.PI * 2) / 4) * amp, y);
        ctx.stroke();
      }
      ctx.fillStyle = grey(0.45, 0.9);
      ctx.fillRect(i * pw, 0, 2, S);
    }
    blotches(ctx, S, rnd, 20, 10, 40, 0.7, 1.0, 0.15);
    return finish(c, this.anisotropy);
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

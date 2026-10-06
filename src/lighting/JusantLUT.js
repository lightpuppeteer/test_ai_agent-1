import * as THREE from 'three';

/**
 * Procedural 3D colour lookup table with the Jusant-style grade, applied in
 * display space by LUTPass after tone mapping:
 *
 *  - soft filmic S-curve with lifted, slightly blue blacks
 *  - split toning: teal-blue shadows, amber highlights (warm/cool contrast)
 *  - hue-selective saturation: warm stone/sand/roof hues richer, greens
 *    pushed towards olive, blues towards a dusty teal sky
 *  - gentle highlight desaturation so the sun glare stays creamy
 *
 * Everything is parameterised, so it doubles as a template: export the
 * generated cube, tweak it in a grading tool and load it back with
 * LUTCubeLoader for hand-authored chapter looks.
 */
export const JUSANT_GRADE = {
  contrast: 0.12, // S-curve strength
  lift: [0.02, 0.026, 0.04], // black level tint (display space)
  shadowTint: [-0.025, 0.004, 0.025],
  highlightTint: [0.035, 0.012, -0.03],
  warmSaturation: 1.12, // reds/oranges/yellows
  greenShift: 0.06, // greens → olive/teal
  blueShift: 0.04, // blues → teal
  highlightDesat: 0.25,
};

const clamp01 = (x) => Math.min(1, Math.max(0, x));
const smooth = (e0, e1, x) => {
  const t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
};

function rgbToHsl(r, g, b) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return [h / 6, s, l];
}

function hslToRgb(h, s, l) {
  if (s === 0) return [l, l, l];
  const hue = (p, q, t) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  return [hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3)];
}

/** Grades one display-space colour. Exported for tests / tooling. */
export function gradeColor(r, g, b, G = JUSANT_GRADE) {
  // 1. Filmic S-curve: blend towards smoothstep (endpoints preserved, mids steeper).
  const s = (x) => x + G.contrast * 2 * (x * x * (3 - 2 * x) - x);
  r = clamp01(s(r));
  g = clamp01(s(g));
  b = clamp01(s(b));

  // 2. Hue-selective adjustments.
  let [h, sat, l] = rgbToHsl(r, g, b);
  const warm = Math.max(smooth(0.2, 0.0, Math.abs(h - 0.08)), smooth(0.08, 0.0, Math.abs(h - 1.0)));
  sat *= 1 + (G.warmSaturation - 1) * warm;
  const green = smooth(0.12, 0.0, Math.abs(h - 0.3));
  h += G.greenShift * green * (h < 0.3 ? -1 : 1) * 0.5;
  const blue = smooth(0.12, 0.0, Math.abs(h - 0.6));
  h -= G.blueShift * blue;
  sat *= 1 - G.highlightDesat * smooth(0.7, 1.0, l);
  [r, g, b] = hslToRgb(((h % 1) + 1) % 1, clamp01(sat), l);

  // 3. Split toning by luminance + lifted blacks.
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const sh = 1 - smooth(0.0, 0.55, lum);
  const hi = smooth(0.45, 1.0, lum);
  const out = [r, g, b].map((c, i) => {
    let v = c + G.shadowTint[i] * sh + G.highlightTint[i] * hi;
    v = G.lift[i] + v * (1 - G.lift[i]);
    return clamp01(v);
  });
  return out;
}

/** Builds the LUT as a Data3DTexture (RGBA8, linear filtering). */
export function createJusantLUT(size = 32, grade = JUSANT_GRADE) {
  const data = new Uint8Array(size * size * size * 4);
  let i = 0;
  for (let bz = 0; bz < size; bz++)
    for (let gy = 0; gy < size; gy++)
      for (let rx = 0; rx < size; rx++) {
        const [r, g, b] = gradeColor(rx / (size - 1), gy / (size - 1), bz / (size - 1), grade);
        data[i++] = Math.round(r * 255);
        data[i++] = Math.round(g * 255);
        data[i++] = Math.round(b * 255);
        data[i++] = 255;
      }
  const tex = new THREE.Data3DTexture(data, size, size, size);
  tex.format = THREE.RGBAFormat;
  tex.type = THREE.UnsignedByteType;
  tex.minFilter = tex.magFilter = THREE.LinearFilter;
  tex.wrapS = tex.wrapT = tex.wrapR = THREE.ClampToEdgeWrapping;
  tex.unpackAlignment = 1;
  tex.needsUpdate = true;
  return tex;
}

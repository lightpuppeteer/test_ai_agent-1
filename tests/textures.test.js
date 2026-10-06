import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createImage, shade, bake, createNoise } from '../src/environment/textures/TextureSynth.js';
import * as Patterns from '../src/environment/textures/Patterns.js';
import { TextureFactory } from '../src/environment/TextureFactory.js';

const decodeNormal = (detail, i) => {
  const x = detail[i * 4] / 127.5 - 1;
  const y = detail[i * 4 + 1] / 127.5 - 1;
  return [x, y, Math.sqrt(Math.max(0, 1 - x * x - y * y))];
};

test('bake: normals match the analytic slope of the relief', () => {
  const S = 64;
  const depth = 0.5; // a 0→1 ramp across a 1 m tile = slope 0.5
  const img = shade(createImage(S), (p, u) => {
    p.h = u;
  });
  const { detail } = bake(img, { tileSize: 1, depth });
  const [nx, ny, nz] = decodeNormal(detail, (S / 2) * S + S / 2);
  const expected = -depth / Math.hypot(depth, 1);
  assert.ok(Math.abs(nx - expected) < 0.01, `nx ${nx} vs ${expected}`);
  assert.ok(Math.abs(ny) < 0.01);
  assert.ok(nz > 0.85);
  // Flat field → neutral encoding, no cavity.
  const flat = bake(
    shade(createImage(8), (p) => (p.h = 0.5)),
    { tileSize: 1, depth: 0.1 },
  );
  assert.deepEqual([...flat.detail.slice(0, 4)], [128, 128, 128, 255]);
});

test('noise and fBm are periodic over the tile', () => {
  const N = createNoise(3);
  for (const v of [0.13, 0.5, 0.91]) {
    assert.ok(Math.abs(N.fbm(0, v, 8, 4) - N.fbm(1, v, 8, 4)) < 1e-9);
    assert.ok(Math.abs(N.fbm2(v, 0, 6, 24, 3) - N.fbm2(v, 1, 6, 24, 3)) < 1e-9);
  }
});

test('every material pattern tiles seamlessly and stays in range', () => {
  const S = 128;
  for (const [name, fn] of Object.entries(Patterns)) {
    const { albedo, detail } = fn({ S });
    assert.equal(albedo.length, S * S * 4, name);
    // The step across each wrap edge must look like an ordinary interior
    // step: compare it with the worst interior column/row boundary.
    const px = (x, y, c) => albedo[(((y + S) % S) * S + ((x + S) % S)) * 4 + c];
    const colStep = (x) => {
      let d = 0;
      for (let y = 0; y < S; y++) for (let c = 0; c < 3; c++) d += Math.abs(px(x, y, c) - px(x - 1, y, c));
      return d / S;
    };
    const rowStep = (y) => {
      let d = 0;
      for (let x = 0; x < S; x++) for (let c = 0; c < 3; c++) d += Math.abs(px(x, y, c) - px(x, y - 1, c));
      return d / S;
    };
    let worstCol = 0;
    let worstRow = 0;
    for (let k = 1; k < S; k++) {
      worstCol = Math.max(worstCol, colStep(k));
      worstRow = Math.max(worstRow, rowStep(k));
    }
    assert.ok(colStep(0) <= worstCol * 1.2 + 1, `${name}: seam along u (${colStep(0)} vs ${worstCol})`);
    assert.ok(rowStep(0) <= worstRow * 1.2 + 1, `${name}: seam along v (${rowStep(0)} vs ${worstRow})`);
    let roughMin = 255;
    let roughMax = 0;
    for (let i = 0; i < S * S; i++) {
      roughMin = Math.min(roughMin, detail[i * 4 + 2]);
      roughMax = Math.max(roughMax, detail[i * 4 + 2]);
    }
    assert.ok(roughMin > 0 && roughMax < 255, `${name}: roughness factor saturates`);
  }
});

test('TextureFactory falls back to synchronous generation without Workers', () => {
  const T = new TextureFactory(null);
  const set = T.set('weave');
  assert.ok(set.map.isDataTexture && set.detail.isDataTexture);
  assert.equal(T.set('weave'), set, 'sets are cached');
  const data = set.detail.image.data;
  assert.equal(data.length, 256 * 256 * 4);
  assert.ok(
    data.some((b, i) => i % 4 === 0 && b !== 128),
    'detail was generated, not left as placeholder',
  );
  assert.equal(T.get('weave'), set.map);
  assert.throws(() => T.set('nope'));
});

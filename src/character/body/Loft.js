import * as THREE from 'three';

/**
 * Lofting: sweeps a superellipse cross-section along a parametric frame to
 * build smooth, low-frequency organic surfaces (torso, limbs, head, hands,
 * shoes) and the garments that wrap them.
 *
 * Section keys are { t, w, f, b, n, dz }:
 *   w   half-width along the frame's `u` axis
 *   f   half-depth on the +v side ("front" — chest, toes, face…)
 *   b   half-depth on the −v side ("back" — buttocks, calves, sole…)
 *   n   superellipse exponent (2 = ellipse, >2 boxier)
 *   dz  offset of the section centre along v
 * Keys are interpolated with Catmull-Rom, so a handful of keys yields smooth
 * curves. The ring/vertex count depends only on the segment definition (not
 * on key values), which is what makes two body profiles morph-compatible.
 *
 * Angle convention: a = 0 along +u, a = π/2 along +v (front), a = 3π/2 back.
 */

const KEYS = ['w', 'f', 'b', 'n', 'dz'];

function catmull(p0, p1, p2, p3, t) {
  const t2 = t * t;
  const t3 = t2 * t;
  return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
}

/** Smoothly interpolated section at parameter t (keys sorted by t). */
export function sampleSection(keys, t, out = {}) {
  const n = keys.length;
  let i = 0;
  while (i < n - 2 && t > keys[i + 1].t) i++;
  const k0 = keys[Math.max(0, i - 1)];
  const k1 = keys[i];
  const k2 = keys[Math.min(n - 1, i + 1)];
  const k3 = keys[Math.min(n - 1, i + 2)];
  const span = k2.t - k1.t || 1;
  const u = THREE.MathUtils.clamp((t - k1.t) / span, 0, 1);
  for (const key of KEYS) {
    const d = key === 'n' ? 2 : 0;
    const v = catmull(k0[key] ?? d, k1[key] ?? d, k2[key] ?? d, k3[key] ?? d, u);
    out[key] = key === 'w' || key === 'f' || key === 'b' ? Math.max(v, 0) : v;
  }
  return out;
}

/** Point on a superellipse section at angle a, in the (u, v) plane. */
export function sectionPoint(sec, a, inflate = 0, out = { x: 0, y: 0 }) {
  const c = Math.cos(a);
  const s = Math.sin(a);
  const e = 2 / Math.max(sec.n, 0.5);
  const px = Math.sign(c) * Math.pow(Math.abs(c), e);
  const py = Math.sign(s) * Math.pow(Math.abs(s), e);
  out.x = px * (sec.w + inflate);
  out.y = py * ((s >= 0 ? sec.f : sec.b) + inflate) + sec.dz;
  return out;
}

const _sec = {};
const _pt = { x: 0, y: 0 };
const _o = new THREE.Vector3();
const _u = new THREE.Vector3();
const _v = new THREE.Vector3();

/**
 * Builds one lofted segment into `acc` (an accumulator shared by all
 * segments of a mesh).
 *
 * @param {object} acc accumulator { positions, skinIndex, skinWeight, bodyUV, triangles }
 * @param {object} seg
 * @param {number} seg.rings number of rings along t ∈ [t0, t1]
 * @param {number} seg.radial vertices per ring
 * @param {number} seg.t0
 * @param {number} seg.t1
 * @param {(t:number, o:THREE.Vector3, u:THREE.Vector3, v:THREE.Vector3) => void} seg.frame
 * @param {object[]} seg.keys section keys
 * @param {(t:number, a:number) => number[][]} seg.weights → [[bone, w], …]
 * @param {(t:number) => number} seg.region → region index
 * @param {boolean} [seg.capStart]
 * @param {boolean} [seg.capEnd]
 * @param {number|((t:number, a:number) => number)} [seg.inflate]
 */
export function loftSegment(acc, seg) {
  const { rings, radial, t0, t1, keys, frame, weights, region } = seg;
  const inflate = typeof seg.inflate === 'function' ? seg.inflate : () => seg.inflate ?? 0;
  const base = acc.positions.length / 3;
  const pushVertex = (x, y, z, t, a) => {
    acc.positions.push(x, y, z);
    const w = weights(t, a).slice(0, 4);
    let sum = 0;
    for (const [, wi] of w) sum += wi;
    for (let k = 0; k < 4; k++) {
      acc.skinIndex.push(w[k] ? w[k][0] : 0);
      acc.skinWeight.push(w[k] ? w[k][1] / sum : 0);
    }
    acc.bodyUV.push(a / (Math.PI * 2), t);
  };

  for (let r = 0; r < rings; r++) {
    const t = t0 + ((t1 - t0) * r) / (rings - 1);
    frame(t, _o, _u, _v);
    sampleSection(keys, t, _sec);
    for (let i = 0; i < radial; i++) {
      const a = (i / radial) * Math.PI * 2;
      sectionPoint(_sec, a, inflate(t, a), _pt);
      pushVertex(
        _o.x + _u.x * _pt.x + _v.x * _pt.y,
        _o.y + _u.y * _pt.x + _v.y * _pt.y,
        _o.z + _u.z * _pt.x + _v.z * _pt.y,
        t,
        a,
      );
    }
  }

  // Orientation check: triangles must face away from the section centre.
  frame(t0 + (t1 - t0) * 0.5, _o, _u, _v);
  const ringMid = Math.floor(rings / 2);
  const ia = base + ringMid * radial;
  const P = acc.positions;
  const pa = new THREE.Vector3(P[ia * 3], P[ia * 3 + 1], P[ia * 3 + 2]);
  const pb = new THREE.Vector3(P[(ia + radial) * 3], P[(ia + radial) * 3 + 1], P[(ia + radial) * 3 + 2]);
  const pc = new THREE.Vector3(P[(ia + 1) * 3], P[(ia + 1) * 3 + 1], P[(ia + 1) * 3 + 2]);
  const nrm = pb.clone().sub(pa).cross(pc.clone().sub(pa));
  const flip = nrm.dot(pa.clone().sub(_o)) < 0;
  const tri = (a, b, c, reg) => (flip ? acc.triangles.push(a, c, b, reg) : acc.triangles.push(a, b, c, reg));

  for (let r = 0; r < rings - 1; r++) {
    const t = t0 + ((t1 - t0) * (r + 0.5)) / (rings - 1);
    const reg = region(t);
    for (let i = 0; i < radial; i++) {
      const a = base + r * radial + i;
      const b = base + (r + 1) * radial + i;
      const c = base + r * radial + ((i + 1) % radial);
      const d = base + (r + 1) * radial + ((i + 1) % radial);
      tri(a, b, c, reg);
      tri(c, b, d, reg);
    }
  }

  // Pole caps (closing fans) — pole sits at the ring centre, pushed outward a bit.
  const cap = (atStart) => {
    const t = atStart ? t0 : t1;
    frame(t, _o, _u, _v);
    sampleSection(keys, t, _sec);
    const along = new THREE.Vector3();
    const tn = atStart ? t0 + (t1 - t0) * 0.02 : t1 - (t1 - t0) * 0.02;
    const o2 = new THREE.Vector3();
    frame(tn, o2, new THREE.Vector3(), new THREE.Vector3());
    along.subVectors(_o, o2).normalize(); // outward along the axis
    const radius = Math.max(_sec.w, (_sec.f + _sec.b) / 2);
    const pole = _o
      .clone()
      .addScaledVector(_v, _sec.dz)
      .addScaledVector(along, radius * 0.35);
    const pi = acc.positions.length / 3;
    pushVertex(pole.x, pole.y, pole.z, t, Math.PI / 2);
    const ring = base + (atStart ? 0 : (rings - 1) * radial);
    const reg = region(t);
    for (let i = 0; i < radial; i++) {
      const a = ring + i;
      const c = ring + ((i + 1) % radial);
      if (atStart) tri(pi, a, c, reg);
      else tri(a, pi, c, reg);
    }
  };
  if (seg.capStart) cap(true);
  if (seg.capEnd) cap(false);
}

export function createAccumulator() {
  return { positions: [], skinIndex: [], skinWeight: [], bodyUV: [], triangles: [] };
}

/**
 * Turns an accumulator into an indexed BufferGeometry whose index is sorted
 * by region, with one geometry group per region (materialIndex 0).
 * Returns { geometry, regionRanges } where regionRanges[region] = {start, count}.
 */
export function accumulatorToGeometry(acc, regionCount) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(acc.positions, 3));
  g.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(acc.skinIndex, 4));
  g.setAttribute('skinWeight', new THREE.Float32BufferAttribute(acc.skinWeight, 4));
  g.setAttribute('aBodyUV', new THREE.Float32BufferAttribute(acc.bodyUV, 2));
  const buckets = Array.from({ length: regionCount }, () => []);
  const T = acc.triangles;
  for (let i = 0; i < T.length; i += 4) buckets[T[i + 3]].push(T[i], T[i + 1], T[i + 2]);
  const index = [];
  const regionRanges = [];
  for (let r = 0; r < regionCount; r++) {
    regionRanges[r] = { start: index.length, count: buckets[r].length };
    if (buckets[r].length) {
      g.addGroup(index.length, buckets[r].length, 0);
      g.groups[g.groups.length - 1].region = r;
    }
    for (const v of buckets[r]) index.push(v);
  }
  g.setIndex(index);
  g.computeVertexNormals();
  return { geometry: g, regionRanges };
}

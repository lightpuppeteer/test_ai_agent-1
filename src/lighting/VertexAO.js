import * as THREE from 'three';
import { GROUPS } from '../config.js';

const _p = new THREE.Vector3();
const _n = new THREE.Vector3();
const _t = new THREE.Vector3();
const _b = new THREE.Vector3();
const _d = new THREE.Vector3();

/** Cosine-weighted hemisphere directions (Fibonacci spiral, deterministic). */
function hemisphereSamples(count) {
  const dirs = [];
  const golden = Math.PI * (3 - Math.sqrt(5));
  for (let i = 0; i < count; i++) {
    const u = (i + 0.5) / count;
    const r = Math.sqrt(u); // cosine weighting
    const phi = i * golden;
    dirs.push(new THREE.Vector3(Math.cos(phi) * r, Math.sqrt(1 - u), Math.sin(phi) * r));
  }
  return dirs;
}

/**
 * Pre-computes per-vertex ambient occlusion by ray casting the *physics*
 * world (Rapier's BVH is already built, so no extra acceleration structure
 * is needed). Writes a float attribute `aAO` (1 = open sky, 0 = enclosed)
 * consumed by stylised materials with `vertexAO: true`.
 *
 * Use on static, world-space geometry (ground patches, terraces). Cost is
 * vertices × samples ray casts at load time.
 *
 * @param {THREE.BufferGeometry} geometry world-space geometry with normals
 * @param {import('../core/PhysicsWorld.js').PhysicsWorld} physics
 */
export function bakeVertexAO(geometry, physics, { samples = 14, radius = 2.6, offset = 0.04, power = 1.3 } = {}) {
  const pos = geometry.attributes.position;
  const nrm = geometry.attributes.normal;
  const ao = new Float32Array(pos.count);
  const dirs = hemisphereSamples(samples);
  const R = physics.RAPIER;
  const ray = new R.Ray({ x: 0, y: 0, z: 0 }, { x: 0, y: 1, z: 0 });

  for (let i = 0; i < pos.count; i++) {
    _p.fromBufferAttribute(pos, i);
    _n.fromBufferAttribute(nrm, i).normalize();
    // Tangent frame around the normal.
    _t.set(Math.abs(_n.y) < 0.9 ? 0 : 1, Math.abs(_n.y) < 0.9 ? 1 : 0, 0)
      .cross(_n)
      .normalize();
    _b.crossVectors(_n, _t);
    let occlusion = 0;
    for (const s of dirs) {
      _d.copy(_t).multiplyScalar(s.x).addScaledVector(_n, s.y).addScaledVector(_b, s.z);
      ray.origin = { x: _p.x + _n.x * offset, y: _p.y + _n.y * offset, z: _p.z + _n.z * offset };
      ray.dir = { x: _d.x, y: _d.y, z: _d.z };
      const hit = physics.world.castRay(ray, radius, true, undefined, GROUPS.QUERY_CAMERA);
      if (hit) occlusion += 1 - hit.timeOfImpact / radius; // near hits occlude more
    }
    ao[i] = Math.pow(1 - occlusion / samples, power);
  }
  geometry.setAttribute('aAO', new THREE.BufferAttribute(ao, 1));
  return geometry;
}

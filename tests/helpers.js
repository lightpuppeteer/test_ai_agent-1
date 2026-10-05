import * as THREE from 'three';
import { PhysicsWorld } from '../src/core/PhysicsWorld.js';

export { THREE };

/** Fresh Rapier world (WASM initialised once per process by the compat package). */
export function createPhysics() {
  return PhysicsWorld.create();
}

/** Deterministic PRNG for reproducible sampling. */
export function lcg(seed = 1) {
  let s = seed;
  return () => (s = (s * 16807) % 2147483647) / 2147483647;
}

/** Up-vector of a Rapier rotation. */
export function upOf(r) {
  return new THREE.Vector3(0, 1, 0).applyQuaternion(new THREE.Quaternion(r.x, r.y, r.z, r.w));
}

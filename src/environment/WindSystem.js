import * as THREE from 'three';
import { sharedUniforms } from '../shaders/common.glsl.js';

// Small deterministic value-noise for CPU-side turbulence (cloth, hair).
function hash3(x, y, z) {
  let h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(z | 0, 2147483647);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}
function noise3(x, y, z) {
  const xi = Math.floor(x),
    yi = Math.floor(y),
    zi = Math.floor(z);
  const xf = x - xi,
    yf = y - yi,
    zf = z - zi;
  const u = xf * xf * (3 - 2 * xf),
    v = yf * yf * (3 - 2 * yf),
    w = zf * zf * (3 - 2 * zf);
  const l = (a, b, t) => a + (b - a) * t;
  return l(
    l(l(hash3(xi, yi, zi), hash3(xi + 1, yi, zi), u), l(hash3(xi, yi + 1, zi), hash3(xi + 1, yi + 1, zi), u), v),
    l(
      l(hash3(xi, yi, zi + 1), hash3(xi + 1, yi, zi + 1), u),
      l(hash3(xi, yi + 1, zi + 1), hash3(xi + 1, yi + 1, zi + 1), u),
      v,
    ),
    w,
  );
}

/**
 * Global wind: one slowly veering prevailing direction with layered gusts.
 *
 *  - GPU side: writes the shared wind uniforms (direction, strength, phase,
 *    integrated offset) consumed by particles, foliage sway, sand ripples,
 *    clouds and ocean detail.
 *  - CPU side: `sample(position, out)` returns a turbulent local wind vector
 *    (m/s) for cloth, spring bones and anything physical.
 */
export class WindSystem {
  constructor({
    direction = new THREE.Vector3(0.45, 0, -0.89), // onshore sea breeze
    baseStrength = 0.55, // 0..1
    gustiness = 0.45,
    maxSpeed = 11, // m/s at strength 1
  } = {}) {
    this.baseAngle = Math.atan2(direction.x, direction.z);
    this.baseStrength = baseStrength;
    this.gustiness = gustiness;
    this.maxSpeed = maxSpeed;

    this.direction = direction.clone().normalize();
    this.strength = baseStrength;
    this.speed = baseStrength * maxSpeed;
    this.time = 0;
    this.uniforms = sharedUniforms;
  }

  update(dt) {
    this.time += dt;
    const t = this.time;

    // Slow veer of the prevailing direction (±~20°).
    const angle = this.baseAngle + 0.22 * Math.sin(t * 0.031) + 0.12 * Math.sin(t * 0.087 + 1.7);
    this.direction.set(Math.sin(angle), 0, Math.cos(angle));

    // Gusts: incommensurate sines + noise → never visibly periodic.
    const g = 0.55 * Math.sin(t * 0.37) + 0.3 * Math.sin(t * 0.91 + 2.1) + 0.35 * (noise3(t * 0.6, 3.1, 7.7) * 2 - 1);
    this.strength = THREE.MathUtils.clamp(this.baseStrength * (1 + this.gustiness * g), 0.05, 1);
    this.speed = this.strength * this.maxSpeed;

    const u = this.uniforms;
    u.uWindDir.value.copy(this.direction);
    u.uWindStrength.value = this.strength;
    u.uWindPhase.value += this.strength * dt;
    u.uWindOffset.value.addScaledVector(this.direction, this.speed * dt);
  }

  /**
   * Turbulent wind velocity at a world position (m/s).
   * @param {THREE.Vector3} p
   * @param {THREE.Vector3} out
   * @param {number} [turbulence] 0..1
   */
  sample(p, out, turbulence = 0.6) {
    const t = this.time;
    const s = 0.35; // spatial frequency of turbulence (1/m)
    const ox = this.uniforms.uWindOffset.value;
    // Advect the turbulence field with the wind so eddies travel downwind.
    const x = (p.x - ox.x) * s;
    const y = p.y * s;
    const z = (p.z - ox.z) * s;
    const n1 = noise3(x, y, z + t * 0.5) * 2 - 1;
    const n2 = noise3(x + 31.7, y, z - t * 0.4) * 2 - 1;
    const n3 = noise3(x, y + 17.3, z + t * 0.7) * 2 - 1;
    const speed = this.speed * (1 + turbulence * 0.6 * n1);
    out.copy(this.direction).multiplyScalar(speed);
    // Cross-wind and vertical eddies.
    out.x += -this.direction.z * n2 * this.speed * turbulence * 0.5;
    out.z += this.direction.x * n2 * this.speed * turbulence * 0.5;
    out.y += n3 * this.speed * turbulence * 0.25;
    return out;
  }
}

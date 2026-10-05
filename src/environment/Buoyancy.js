import * as THREE from 'three';
import { PHYSICS } from '../config.js';

const _p = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _waterVel = new THREE.Vector3();
const _rel = new THREE.Vector3();
const _f = new THREE.Vector3();

/**
 * Sample-point buoyancy against the Gerstner surface.
 *
 * Each floating body is approximated by N sample points, each owning an equal
 * share of the body's displaced volume and a vertical extent `cellHeight`.
 * Per fixed step and per sample:
 *
 *   submersion  s = clamp((waterY - (p.y - h/2)) / h, 0, 1)
 *   buoyancy    F_b = ρ · g · (V / N) · s                     (Archimedes)
 *   drag        F_d = -c · s · (v_point - v_water)            (relative to orbital velocity)
 *
 * Forces are applied as impulses at the sample points, so torques (righting
 * moment, pitching on swells) emerge naturally. Because the water height and
 * orbital velocity come from the CPU mirror of the ocean shader, objects ride
 * exactly the waves you see.
 */
export class BuoyancySystem {
  /**
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} physics
   * @param {import('./GerstnerWaves.js').GerstnerWaves} waves
   */
  constructor(physics, waves) {
    this.physics = physics;
    this.waves = waves;
    this.bodies = [];
  }

  /**
   * @param {RAPIER.RigidBody} body
   * @param {object} opts
   * @param {THREE.Vector3[]} opts.samples local-space sample points
   * @param {number} opts.volume displaced volume when fully submerged (m³)
   * @param {number} opts.cellHeight vertical extent represented by each sample (m)
   * @param {number} [opts.linearDrag] N·s/m per fully-submerged sample
   * @param {number} [opts.angularDrag] extra angular damping while submerged
   */
  add(body, { samples, volume, cellHeight, linearDrag = 60, angularDrag = 0.8 }) {
    const entry = { body, samples, volume, cellHeight, linearDrag, angularDrag, submerged: 0 };
    this.bodies.push(entry);
    return entry;
  }

  remove(body) {
    this.bodies = this.bodies.filter((b) => b.body !== body);
  }

  /** Box-shaped sample lattice helper (nx·ny·nz points filling the box). */
  static boxSamples(size, nx = 2, ny = 2, nz = 2) {
    const pts = [];
    for (let i = 0; i < nx; i++)
      for (let j = 0; j < ny; j++)
        for (let k = 0; k < nz; k++)
          pts.push(
            new THREE.Vector3(
              ((i + 0.5) / nx - 0.5) * size.x,
              ((j + 0.5) / ny - 0.5) * size.y,
              ((k + 0.5) / nz - 0.5) * size.z,
            ),
          );
    return { samples: pts, cellHeight: size.y / ny, volume: size.x * size.y * size.z };
  }

  fixedUpdate(dt, simTime) {
    const g = -PHYSICS.gravity;
    const rho = PHYSICS.waterDensity;
    // Forces are applied for the step that ends at simTime + dt; sample the
    // surface at mid-step for a tiny accuracy gain.
    const t = simTime + dt * 0.5;

    for (const e of this.bodies) {
      const b = e.body;
      if (b.isSleeping()) {
        // Wake periodically if we are in the water — waves keep moving.
        const tr = b.translation();
        if (this.waves.heightAt(tr.x, tr.z, t) > tr.y - 2) b.wakeUp();
        else continue;
      }
      const tr = b.translation();
      const r = b.rotation();
      _q.set(r.x, r.y, r.z, r.w);

      const n = e.samples.length;
      const vShare = e.volume / n;
      const h = e.cellHeight;
      let submergedSum = 0;

      for (const s of e.samples) {
        _p.copy(s).applyQuaternion(_q).add(tr);
        const waterY = this.waves.heightAt(_p.x, _p.z, t, _waterVel);
        const sub = THREE.MathUtils.clamp((waterY - (_p.y - h * 0.5)) / h, 0, 1);
        if (sub <= 0) continue;
        submergedSum += sub;

        // Archimedes
        _f.set(0, rho * g * vShare * sub, 0);

        // Linear drag against the water's orbital motion (pushes floaters with the swell).
        const pv = b.velocityAtPoint({ x: _p.x, y: _p.y, z: _p.z });
        _rel.set(pv.x - _waterVel.x, pv.y - _waterVel.y, pv.z - _waterVel.z);
        _f.addScaledVector(_rel, -e.linearDrag * sub);

        b.applyImpulseAtPoint({ x: _f.x * dt, y: _f.y * dt, z: _f.z * dt }, { x: _p.x, y: _p.y, z: _p.z }, true);
      }

      e.submerged = submergedSum / n;
      // Rotational damping proportional to submersion (water resists tumbling).
      if (e.submerged > 0) {
        const av = b.angvel();
        const k = Math.exp(-e.angularDrag * e.submerged * dt);
        b.setAngvel({ x: av.x * k, y: av.y * k, z: av.z * k }, true);
      }
    }
  }
}

import * as THREE from 'three';
import { GROUPS, SURFACE, WORLD } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { sandHeight, sandNormal } from './Terrain.js';

const UP = new THREE.Vector3(0, 1, 0);
const _n = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();
const _c = new THREE.Color();
const _m = new THREE.Matrix4();

function mulberry(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Beach micro-detail: thousands of pebbles (one instanced draw call),
 * concentrated along the strand line and the foot of the sea wall, and
 * bleached driftwood logs (some half-buried) with static colliders.
 */
export class BeachDressing {
  /**
   * @param {object} o
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} o.physics
   * @param {{x:number, z:number, r:number}[]} [o.avoid] circles to keep clear (towels)
   */
  constructor({ physics, avoid = [] }) {
    this.physics = physics;
    this.avoid = avoid;
    this.group = new THREE.Group();
    this.group.name = 'BeachDressing';
    this.rng = mulberry(4242);
  }

  build({ pebbles = 3200, logs = 7 } = {}) {
    this._pebbles(pebbles);
    for (let i = 0; i < logs; i++) this._driftwood(i);
    return this;
  }

  _clear(x, z) {
    for (const a of this.avoid) if ((x - a.x) ** 2 + (z - a.z) ** 2 < a.r * a.r) return false;
    return true;
  }

  /**
   * Rejection-sampled density: strand line (just above the swash), the
   * wrack line further up, the foot of the promenade wall, sparse elsewhere.
   */
  _pebbleDensity(z, h) {
    const strand = Math.exp(-(((h - 0.35) / 0.35) ** 2));
    const wrack = 0.6 * Math.exp(-(((h - 1.1) / 0.25) ** 2));
    const wall = 0.8 * Math.exp(-(((z - WORLD.beach.zMin) / 2.5) ** 2));
    return 0.08 + strand + wrack + wall;
  }

  _pebbles(count) {
    const rng = this.rng;
    const geometry = new THREE.IcosahedronGeometry(1, 1);
    const material = createStylizedMaterial({
      name: 'Pebble',
      color: 0xffffff,
      roughness: 0.55,
      wrap: 0.4,
      rim: 0.1,
      painterly: 0.12,
      painterlyScale: 4,
    });
    const mesh = new THREE.InstancedMesh(geometry, material, count);
    const B = WORLD.beach;
    let placed = 0;
    let guard = 0;
    while (placed < count && guard++ < count * 30) {
      const x = B.xMin + 4 + rng() * (B.xMax - B.xMin - 8);
      const z = B.zMin + 0.6 + rng() * 75;
      const h = sandHeight(x, z);
      if (h < WORLD.waterLevel - 0.3) continue; // under water: skip
      if (rng() * 2.2 > this._pebbleDensity(z, h) || !this._clear(x, z)) continue;
      const r = 0.012 + rng() * rng() * 0.06;
      sandNormal(x, z, _n);
      _q.setFromUnitVectors(UP, _n).multiply(_q2.setFromAxisAngle(UP, rng() * Math.PI * 2));
      _q.multiply(_q2.setFromEuler(new THREE.Euler((rng() - 0.5) * 0.6, 0, (rng() - 0.5) * 0.6)));
      _p.set(x, h + r * 0.25, z);
      _m.compose(_p, _q, _s.set(r * (1 + rng() * 0.6), r * (0.45 + rng() * 0.25), r * (0.9 + rng() * 0.4)));
      mesh.setMatrixAt(placed, _m);
      // Granite greys, warm browns and the odd white quartz pebble.
      const k = rng();
      if (k < 0.12) _c.setRGB(0.92, 0.9, 0.86);
      else if (k < 0.55) _c.setHSL(0.08 + rng() * 0.04, 0.12 + rng() * 0.1, 0.32 + rng() * 0.2);
      else _c.setHSL(0.6, 0.03, 0.35 + rng() * 0.22);
      mesh.setColorAt(placed, _c);
      placed++;
    }
    mesh.count = placed;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.castShadow = false;
    mesh.receiveShadow = true;
    mesh.computeBoundingSphere();
    mesh.name = 'Pebbles';
    this.group.add(mesh);
    this.pebbles = mesh;
  }

  /** A bent, tapered log with a branch stub; partially sunk into the sand. */
  _driftwood(index) {
    const rng = this.rng;
    const material =
      this._woodMat ??
      (this._woodMat = createStylizedMaterial({
        name: 'Driftwood',
        color: 0xb9ab95,
        roughness: 0.95,
        wrap: 0.5,
        painterly: 0.2,
        painterlyScale: 3,
      }));
    // Place along the strand line or the upper beach.
    let x;
    let z;
    let h;
    for (let tries = 0; tries < 40; tries++) {
      x = -95 + rng() * 190;
      z = index % 2 ? 16 + rng() * 10 : -25 + rng() * 25;
      h = sandHeight(x, z);
      if (h > WORLD.waterLevel + 0.25 && this._clear(x, z)) break;
    }
    const length = 1.6 + rng() * 2.2;
    const radius = 0.07 + rng() * 0.08;
    const pts = [];
    const bend = (rng() - 0.5) * 0.5;
    for (let i = 0; i <= 4; i++) {
      const t = i / 4 - 0.5;
      pts.push(new THREE.Vector3(t * length, 0, Math.sin(t * Math.PI) * bend));
    }
    const curve = new THREE.CatmullRomCurve3(pts);
    const geo = new THREE.TubeGeometry(curve, 20, radius, 8, false);
    // Taper towards one end.
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const t = THREE.MathUtils.clamp(pos.getX(i) / length + 0.5, 0, 1);
      const k = 1 - 0.45 * t;
      const cz = Math.sin((t - 0.5) * Math.PI) * bend;
      pos.setY(i, pos.getY(i) * k);
      pos.setZ(i, cz + (pos.getZ(i) - cz) * k);
    }
    geo.computeVertexNormals();
    const log = new THREE.Mesh(geo, material);
    const yaw = rng() * Math.PI;
    sandNormal(x, z, _n);
    log.quaternion.setFromUnitVectors(UP, _n).multiply(_q2.setFromAxisAngle(UP, yaw));
    log.position.set(x, h + radius * (0.4 - rng() * 0.5), z); // some half-buried
    log.castShadow = true;
    log.receiveShadow = true;
    // Branch stub.
    const stub = new THREE.Mesh(new THREE.CylinderGeometry(radius * 0.25, radius * 0.45, 0.45, 6), material);
    stub.position.set(length * (0.1 + rng() * 0.2), radius * 0.6, 0);
    stub.rotation.set(0.9, 0, -0.8);
    stub.castShadow = true;
    log.add(stub);
    this.group.add(log);

    // Collider: a capsule along the log for the bigger ones (walkable over).
    if (radius > 0.1) {
      log.updateMatrixWorld();
      const R = this.physics.RAPIER;
      const axisQ = log.quaternion.clone().multiply(_q2.setFromAxisAngle(new THREE.Vector3(0, 0, 1), Math.PI / 2));
      const body = this.physics.createRigidBody(
        R.RigidBodyDesc.fixed()
          .setTranslation(log.position.x, log.position.y, log.position.z)
          .setRotation({ x: axisQ.x, y: axisQ.y, z: axisQ.z, w: axisQ.w }),
      );
      this.physics.createCollider(
        R.ColliderDesc.capsule(length * 0.45, radius)
          .setCollisionGroups(GROUPS.STATIC)
          .setFriction(0.8),
        body,
        { surface: SURFACE.WOOD, owner: 'driftwood' },
      );
    }
  }
}

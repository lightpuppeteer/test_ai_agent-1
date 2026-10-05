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
 * concentrated along the strand line and the foot of the sea wall, ribbed
 * scallop and cockle shells, mussel shells, strands of seaweed wrack, and
 * bleached driftwood logs (some half-buried) with static colliders.
 */
export class BeachDressing {
  /**
   * @param {object} o
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} o.physics
   * @param {{x:number, z:number, r:number}[]} [o.avoid] circles to keep clear (towels)
   * @param {import('./TextureFactory.js').TextureFactory} [o.textures]
   */
  constructor({ physics, avoid = [], textures = null }) {
    this.physics = physics;
    this.avoid = avoid;
    this.textures = textures;
    this.group = new THREE.Group();
    this.group.name = 'BeachDressing';
    this.rng = mulberry(4242);
  }

  build({ pebbles = 3200, logs = 7, shells = 420, wrack = 140 } = {}) {
    this._pebbles(pebbles);
    for (let i = 0; i < logs; i++) this._driftwood(i);
    this.rng2 = mulberry(9090); // shells & wrack: never disturb the pebble/log layout
    this._shells(shells);
    this._wrack(wrack);
    return this;
  }

  /** Random point on the beach weighted by the pebble density (strand / wrack lines). */
  _scatter(rng, out) {
    const B = WORLD.beach;
    for (let guard = 0; guard < 60; guard++) {
      const x = B.xMin + 4 + rng() * (B.xMax - B.xMin - 8);
      const z = B.zMin + 0.6 + rng() * 75;
      const h = sandHeight(x, z);
      if (h < WORLD.waterLevel - 0.1) continue;
      if (rng() * 1.6 > this._pebbleDensity(z, h) || !this._clear(x, z)) continue;
      return out.set(x, h, z);
    }
    return null;
  }

  /** Instanced mesh helper: lays `count` instances on the sand via `place(i, p, n)`. */
  _instances(name, geometry, material, count, place) {
    const mesh = new THREE.InstancedMesh(geometry, material, count);
    let placed = 0;
    for (let i = 0; i < count; i++) {
      if (!this._scatter(this.rng2, _p)) continue;
      sandNormal(_p.x, _p.z, _n);
      place(placed, _p, _n, mesh);
      placed++;
    }
    mesh.count = placed;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.castShadow = false;
    mesh.receiveShadow = true;
    mesh.computeBoundingSphere();
    mesh.name = name;
    this.group.add(mesh);
    return mesh;
  }

  _shells(count) {
    const rng = this.rng2;
    // Ribbed scallop: a shallow fan-shaped dome with radial ribs and a hinge.
    const scallop = new THREE.SphereGeometry(1, 12, 4, Math.PI * 0.15, Math.PI * 0.7, 0, Math.PI / 2);
    const pos = scallop.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i);
      const z = pos.getZ(i);
      const phi = Math.atan2(z, x);
      const r = Math.hypot(x, z);
      const rib = 1 + 0.07 * Math.cos(phi * 17) * r;
      pos.setXYZ(i, x * rib, pos.getY(i) * 0.32 * rib, z * rib - 0.45);
    }
    scallop.computeVertexNormals();
    const shellMat = createStylizedMaterial({
      name: 'Shell',
      color: 0xffffff,
      roughness: 0.5,
      wrap: 0.5,
      rim: 0.25,
      painterly: 0.1,
      painterlyScale: 6,
      side: THREE.DoubleSide,
    });
    this._instances('Shells', scallop, shellMat, count, (i, p, n, mesh) => {
      const r = 0.025 + rng() * 0.03;
      const flip = rng() < 0.35; // some lie hollow side up
      _q.setFromUnitVectors(UP, _n.copy(n)).multiply(_q2.setFromAxisAngle(UP, rng() * Math.PI * 2));
      if (flip) _q.multiply(_q2.setFromAxisAngle(new THREE.Vector3(1, 0, 0), Math.PI));
      _m.compose(_p.set(p.x, p.y + (flip ? r * 0.3 : 0.003), p.z), _q, _s.set(r, r, r));
      mesh.setMatrixAt(i, _m);
      const k = rng();
      if (k < 0.45) _c.setRGB(0.95, 0.92, 0.86);
      else if (k < 0.7) _c.setHSL(0.04 + rng() * 0.04, 0.45, 0.72);
      else if (k < 0.85) _c.setHSL(0.08, 0.55, 0.62);
      else _c.setHSL(0.95, 0.3, 0.78);
      mesh.setColorAt(i, _c);
    });
    // Mussels: dark, glossy, elongated.
    const mussel = new THREE.SphereGeometry(1, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2);
    const musselMat = createStylizedMaterial({
      name: 'Mussel',
      color: 0x1d2433,
      roughness: 0.3,
      rim: 0.3,
      painterly: 0.08,
    });
    this._instances('Mussels', mussel, musselMat, Math.round(count * 0.35), (i, p, n, mesh) => {
      const r = 0.018 + rng() * 0.015;
      _q.setFromUnitVectors(UP, n).multiply(_q2.setFromAxisAngle(UP, rng() * Math.PI * 2));
      _m.compose(_p.set(p.x, p.y + 0.002, p.z), _q, _s.set(r * 2.2, r * 0.7, r));
      mesh.setMatrixAt(i, _m);
    });
  }

  /** Strands of wrack (kelp / bladderwrack) lying along the tide lines. */
  _wrack(count) {
    const rng = this.rng2;
    const curve = new THREE.CatmullRomCurve3(
      Array.from({ length: 6 }, (_, k) => new THREE.Vector3(k * 0.12 - 0.3, 0, Math.sin(k * 1.7) * 0.05)),
    );
    const geometry = new THREE.TubeGeometry(curve, 16, 0.012, 4, false);
    geometry.scale(1, 0.45, 1);
    // A few bladders along the strand.
    const material = createStylizedMaterial({
      name: 'Wrack',
      color: 0xffffff,
      roughness: 0.32,
      wrap: 0.4,
      rim: 0.2,
      painterly: 0.15,
      painterlyScale: 5,
    });
    this._instances('Wrack', geometry, material, count, (i, p, n, mesh) => {
      const s = 0.7 + rng() * 0.9;
      _q.setFromUnitVectors(UP, n).multiply(_q2.setFromAxisAngle(UP, rng() * Math.PI * 2));
      _m.compose(_p.set(p.x, p.y + 0.004, p.z), _q, _s.set(s, 1, s * (0.6 + rng())));
      mesh.setMatrixAt(i, _m);
      if (rng() < 0.6) _c.setHSL(0.17 + rng() * 0.05, 0.45, 0.16 + rng() * 0.06);
      else _c.setHSL(0.09, 0.5, 0.14 + rng() * 0.06);
      mesh.setColorAt(i, _c);
    });
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
        ...(this.textures && {
          map: this.textures.set('bark').map,
          detailMap: this.textures.set('bark').detail,
          triplanarScale: 2.5,
          normalScale: 0.8,
        }),
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

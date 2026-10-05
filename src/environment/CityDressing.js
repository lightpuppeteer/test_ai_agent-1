import * as THREE from 'three';
import { PALETTE, SURFACE } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { VerletCloth } from '../simulation/VerletCloth.js';
import { cityGroundHeight } from './CityBuilder.js';

const UP = new THREE.Vector3(0, 1, 0);
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();
const _right = new THREE.Vector3();
const _c = new THREE.Color();

function mulberry(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Collects instance transforms (+ optional colours) and emits one InstancedMesh. */
class InstanceSet {
  constructor(geometry, material, { castShadow = true, receiveShadow = true, name } = {}) {
    Object.assign(this, { geometry, material, castShadow, receiveShadow, name });
    this.matrices = [];
    this.colors = [];
  }

  add(position, quaternion, scale, color = null) {
    this.matrices.push(new THREE.Matrix4().compose(position, quaternion, scale));
    this.colors.push(color ? color.clone() : null);
  }

  build(parent) {
    if (this.matrices.length === 0) return null;
    const mesh = new THREE.InstancedMesh(this.geometry, this.material, this.matrices.length);
    this.matrices.forEach((m, i) => mesh.setMatrixAt(i, m));
    if (this.colors.some(Boolean)) this.colors.forEach((c, i) => mesh.setColorAt(i, c ?? _c.set(1, 1, 1)));
    mesh.castShadow = this.castShadow;
    mesh.receiveShadow = this.receiveShadow;
    mesh.computeBoundingSphere();
    mesh.matrixAutoUpdate = false;
    mesh.name = this.name ?? this.material.name;
    parent.add(mesh);
    return mesh;
  }
}

/** Ivy leaf: 3-lobed silhouette in XY, base at the origin, tip at +Y, normal +Z. */
function ivyLeafGeometry() {
  const pts = [
    [0, 0],
    [0.42, 0.28],
    [0.5, 0.55],
    [0.26, 0.62],
    [0.18, 0.92],
    [0, 1],
    [-0.18, 0.92],
    [-0.26, 0.62],
    [-0.5, 0.55],
    [-0.42, 0.28],
  ];
  const shape = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, y)));
  const g = new THREE.ShapeGeometry(shape);
  g.computeVertexNormals();
  return g;
}

/**
 * Old-town set dressing that breaks up repetition and adds vertical layers:
 *  - climbing ivy grown procedurally up selected façades (instanced leaves
 *    + stems, per-instance tint, leaves flutter in the wind)
 *  - granite rubble at wall bases and corners
 *  - heraldic banners and battlement pennants simulated as Verlet cloth in
 *    the global wind (distance-LOD: frozen when far from the camera)
 *  - crate stacks and terracotta planters with swaying plants (with colliders)
 */
export class CityDressing {
  /**
   * @param {object} o
   * @param {import('./CityBuilder.js').CityBuilder} o.city
   * @param {import('./TextureFactory.js').TextureFactory} o.textures
   * @param {import('./WindSystem.js').WindSystem} o.wind
   */
  constructor({ city, textures, wind }) {
    this.city = city;
    this.textures = textures;
    this.wind = wind;
    this.group = new THREE.Group();
    this.group.name = 'CityDressing';
    this.rng = mulberry(1234);
    this.cloths = [];
    this.windAt = (p, out) => wind.sample(p, out, 0.8);

    const S = createStylizedMaterial;
    const tex = (n) => textures.set(n);
    this.mat = {
      leaf: S({
        name: 'IvyLeaf',
        color: 0xffffff,
        side: THREE.DoubleSide,
        roughness: 0.6,
        wrap: 0.75,
        softness: 0.8,
        rim: 0.3,
        painterly: 0.12,
        windSway: 0.035,
        heightGradient: [0, 1, 0.15],
      }),
      stem: S({ name: 'IvyStem', color: 0x4f3d2b, roughness: 0.9 }),
      rubble: S({
        name: 'Rubble',
        color: 0xffffff,
        roughness: 0.92,
        painterly: 0.14,
        painterlyScale: 2,
        detailMap: tex('stucco').detail,
        triplanarScale: 2,
        normalScale: 1.6,
      }),
      crate: S({
        name: 'DressingCrate',
        color: 0x9a7048,
        map: tex('wood').map,
        detailMap: tex('wood').detail,
        triplanarScale: 1.6,
        roughness: 0.85,
      }),
      crateBand: S({
        name: 'DressingCrateBand',
        color: PALETTE.ironwork,
        roughness: 0.5,
        metalness: 0.6,
        map: tex('castIron').map,
        detailMap: tex('castIron').detail,
        triplanarScale: 3,
      }),
      pot: S({
        name: 'Terracotta',
        color: 0xb5643f,
        roughness: 0.8,
        painterly: 0.1,
        painterlyScale: 1.5,
        map: tex('terracotta').map,
        detailMap: tex('terracotta').detail,
        triplanarScale: 2,
      }),
      plant: S({
        name: 'PotPlant',
        color: PALETTE.foliage,
        roughness: 0.7,
        wrap: 0.8,
        softness: 0.8,
        rim: 0.35,
        painterly: 0.2,
        painterlyScale: 1.2,
        windSway: 0.1,
        heightGradient: [-1, 1, 0.25],
        map: tex('leaves').map,
        detailMap: tex('leaves').detail,
        triplanarScale: 2.5,
      }),
      pole: S({
        name: 'FlagPole',
        color: PALETTE.ironwork,
        roughness: 0.45,
        metalness: 0.7,
        detailMap: tex('castIron').detail,
        triplanarScale: 2,
      }),
    };
    this.geo = {
      leaf: ivyLeafGeometry(),
      box: new THREE.BoxGeometry(1, 1, 1),
      stone: new THREE.IcosahedronGeometry(1, 0),
      pot: new THREE.LatheGeometry(
        [
          [0.0, 0],
          [0.17, 0],
          [0.2, 0.05],
          [0.27, 0.32],
          [0.29, 0.44],
          [0.31, 0.47],
          [0.27, 0.48],
        ].map(([x, y]) => new THREE.Vector2(x, y)),
        14,
      ),
      clump: new THREE.IcosahedronGeometry(1, 1),
      pole: new THREE.CylinderGeometry(0.03, 0.035, 1, 8).translate(0, 0.5, 0),
    };
    this.sets = {
      leaves: new InstanceSet(this.geo.leaf, this.mat.leaf, { castShadow: true, name: 'IvyLeaves' }),
      stems: new InstanceSet(this.geo.box, this.mat.stem, { castShadow: false, name: 'IvyStems' }),
      rubble: new InstanceSet(this.geo.stone, this.mat.rubble, { name: 'Rubble' }),
      crates: new InstanceSet(this.geo.box, this.mat.crate, { name: 'Crates' }),
      bands: new InstanceSet(this.geo.box, this.mat.crateBand, { castShadow: false, name: 'CrateBands' }),
      pots: new InstanceSet(this.geo.pot, this.mat.pot, { name: 'Pots' }),
      plants: new InstanceSet(this.geo.clump, this.mat.plant, { name: 'PotPlants' }),
      poles: new InstanceSet(this.geo.pole, this.mat.pole, { name: 'Poles' }),
    };
  }

  build() {
    const rng = this.rng;
    for (const f of this.city.facades) {
      if (f.length < 3) continue;
      if (rng() < 0.32) this._ivy(f, (rng() - 0.5) * (f.length - 2.5), 1.2 + rng() * 2.2);
      this._rubble(f);
      if (rng() < 0.38 || f.tavern) this._props(f);
    }
    for (const m of this.city.bannerMounts) this._banner(m);
    for (const m of this.city.pennantMounts) this._pennant(m);
    for (const set of Object.values(this.sets)) set.build(this.group);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  /** Point on a façade: u along the wall, y absolute, out = distance from the wall. */
  _onWall(f, u, y, out, target = new THREE.Vector3()) {
    _right.set(Math.cos(f.yaw), 0, -Math.sin(f.yaw));
    return target.copy(f.center).addScaledVector(_right, u).addScaledVector(f.normal, out).setY(y);
  }

  // ---------------------------------------------------------------------------
  // Ivy
  // ---------------------------------------------------------------------------
  /**
   * Grows a patch: a few stems random-walk upwards from the ground, wiggling
   * sideways, with leaves budding along them. Leaves face out of the wall
   * with random roll/tilt and size, tinted per instance.
   */
  _ivy(f, uCenter, width) {
    const rng = this.rng;
    const maxH = Math.min(f.top - f.ground - 0.5, 3.5 + rng() * 5.5);
    const stems = 3 + Math.floor(rng() * 3);
    const wallQ = _q.setFromAxisAngle(UP, f.yaw).clone();
    for (let s = 0; s < stems; s++) {
      let u = uCenter + (rng() - 0.5) * width;
      let y = f.ground;
      const top = f.ground + maxH * (0.55 + rng() * 0.45);
      const prev = new THREE.Vector3();
      this._onWall(f, u, y, 0.03, prev);
      let du = (rng() - 0.5) * 0.04;
      while (y < top) {
        du = THREE.MathUtils.clamp(du + (rng() - 0.5) * 0.05, -0.08, 0.08);
        u += du;
        y += 0.09 + rng() * 0.05;
        const cur = this._onWall(f, u, y, 0.03);
        // Stem segment.
        const mid = prev.clone().add(cur).multiplyScalar(0.5);
        const dir = cur.clone().sub(prev);
        const len = dir.length();
        _q2.setFromUnitVectors(UP, dir.normalize());
        this.sets.stems.add(mid, _q2, _s.set(0.018, len, 0.018));
        prev.copy(cur);
        // Leaves: denser near the bottom of the stem.
        const leaves = 2 + Math.floor(rng() * 2);
        for (let l = 0; l < leaves; l++) {
          const lu = u + (rng() - 0.5) * 0.32;
          const ly = y + (rng() - 0.5) * 0.12;
          const pos = this._onWall(f, lu, ly, 0.03 + rng() * 0.07);
          const q = wallQ
            .clone()
            .multiply(_q2.setFromEuler(new THREE.Euler(-0.5 - rng() * 0.6, 0, (rng() - 0.5) * 2.4)));
          const size = 0.07 + rng() * 0.08;
          const tint = _c.setHSL(0.24 + rng() * 0.06, 0.38 + rng() * 0.2, 0.2 + rng() * 0.12);
          this.sets.leaves.add(pos, q, _s.set(size, size, size), tint);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Rubble
  // ---------------------------------------------------------------------------
  _rubble(f) {
    const rng = this.rng;
    const n = 2 + Math.floor(rng() * 5);
    for (let i = 0; i < n; i++) {
      // Bias towards the wall corners.
      const side = rng() < 0.5 ? -1 : 1;
      const u = side * (f.length / 2 - rng() * rng() * f.length * 0.5);
      const out = 0.05 + rng() * 0.35;
      const pos = this._onWall(f, u, 0, out);
      const g = cityGroundHeight(pos.x, pos.z) ?? f.ground;
      const r = 0.05 + rng() * rng() * 0.18;
      pos.y = g + r * 0.35;
      _q2.setFromEuler(new THREE.Euler(rng() * 6, rng() * 6, rng() * 6));
      const grey = 0.5 + rng() * 0.25;
      this.sets.rubble.add(
        pos,
        _q2,
        _s.set(r * (1 + rng() * 0.5), r * 0.6, r),
        _c.setRGB(grey * 1.02, grey, grey * 0.95),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Crates & planters (with colliders)
  // ---------------------------------------------------------------------------
  _props(f) {
    const rng = this.rng;
    const colliders = this.city.colliders;
    const side = rng() < 0.5 ? -1 : 1;
    const u = side * (f.length / 2 - 0.7 - rng() * Math.max(0, f.length / 2 - 2.2));
    const wallQ = new THREE.Quaternion().setFromAxisAngle(UP, f.yaw);
    if (rng() < 0.5 || f.tavern) {
      // Crate stack.
      const n = 1 + Math.floor(rng() * 3);
      for (let i = 0; i < n; i++) {
        const s = 0.5 + rng() * 0.2;
        const pos = this._onWall(f, u + (i === 2 ? 0 : i * 0.62 - 0.3), 0, 0.12 + s / 2);
        const g = cityGroundHeight(pos.x, pos.z) ?? f.ground;
        pos.y = g + s / 2 + (i === 2 ? 0.62 : 0);
        const q = wallQ.clone().multiply(_q2.setFromAxisAngle(UP, (rng() - 0.5) * 0.5));
        this.sets.crates.add(pos, q, _s.set(s, s, s));
        this.sets.bands.add(pos, q, _s.set(s + 0.01, 0.05, s + 0.01));
        colliders.addBox(pos, _s.set(s, s, s), q, { surface: SURFACE.WOOD });
      }
    } else {
      // Two or three planters.
      const n = 2 + Math.floor(rng() * 2);
      for (let i = 0; i < n; i++) {
        const sc = 0.9 + rng() * 0.5;
        const pos = this._onWall(f, u + i * 0.62 * side * -1, 0, 0.42);
        const g = cityGroundHeight(pos.x, pos.z) ?? f.ground;
        pos.y = g;
        this.sets.pots.add(pos, _q2.identity(), _s.set(sc, sc, sc));
        const plant = pos.clone();
        plant.y += 0.48 * sc + 0.16 * sc;
        const r = 0.22 * sc;
        this.sets.plants.add(plant, _q2.setFromAxisAngle(UP, rng() * 6), _s.set(r * 1.2, r * 0.9, r * 1.2));
        colliders.addCylinder(_p.copy(pos).setY(g + 0.24 * sc), 0.24 * sc, 0.28 * sc);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Banners & pennants (Verlet cloth in the global wind)
  // ---------------------------------------------------------------------------
  _banner(m) {
    const cols = 8;
    const rows = 13;
    const design = this.cloths.length % 3;
    const material = createStylizedMaterial({
      name: `Banner${design}`,
      color: 0xffffff,
      map: this.textures.banner(design),
      side: THREE.DoubleSide,
      roughness: 0.85,
      wrap: 0.7,
      rim: 0.25,
      painterly: 0.06,
      alphaTest: 0.5,
      detailMap: this.textures.set('weave').detail,
      detailRepeat: [10, 26],
    });
    const cloth = new VerletCloth({
      cols,
      rows,
      material,
      mass: 0.03,
      iterations: 6,
      drag: 0.5,
      collisionMargin: 0.02,
      initial: (i, j, out) =>
        out.set(m.top.x + (i / (cols - 1) - 0.5) * m.width, m.top.y - 0.03 - (j / (rows - 1)) * m.length, m.top.z),
      isPinned: (_i, j) => j === 0,
    });
    // Keep the banner in front of the wall it hangs on.
    cloth.planes.push({ normal: m.wall.normal.clone(), constant: -m.wall.normal.z * m.wall.z });
    cloth.mesh.castShadow = true;
    this.group.add(cloth.mesh);
    this.cloths.push({ cloth, center: m.top.clone() });
  }

  _pennant(m) {
    const cols = 11;
    const rows = 6;
    this.sets.poles.add(m.base, _q2.identity(), _s.set(1, m.height, 1));
    const material = createStylizedMaterial({
      name: 'Pennant',
      color: 0xffffff,
      map: this.textures.banner(2),
      side: THREE.DoubleSide,
      roughness: 0.85,
      wrap: 0.7,
      rim: 0.25,
      painterly: 0.06,
      alphaTest: 0.5,
      detailMap: this.textures.set('weave').detail,
      detailRepeat: [10, 26],
    });
    const top = m.base.y + m.height - 0.05;
    const length = 1.7;
    const height = 0.8;
    const dir = this.wind.direction;
    const cloth = new VerletCloth({
      cols,
      rows,
      material,
      mass: 0.012,
      iterations: 5,
      drag: 0.55,
      // Pennant tapers: rows shrink towards the free end; pinned along the pole.
      initial: (i, j, out) => {
        const u = i / (cols - 1);
        const v = j / (rows - 1) - 0.5;
        out.set(
          m.base.x + dir.x * u * length,
          top - height * 0.5 + v * height * (1 - 0.7 * u),
          m.base.z + dir.z * u * length,
        );
      },
      isPinned: (i) => i === 0,
    });
    this.group.add(cloth.mesh);
    this.cloths.push({ cloth, center: m.base.clone().setY(top) });
  }

  /** Simulates nearby cloth only (distance LOD). */
  update(dt, cameraPosition) {
    for (const c of this.cloths) {
      c.cloth.active = c.center.distanceToSquared(cameraPosition) < 95 * 95;
      c.cloth.update(dt, this.windAt);
    }
  }
}

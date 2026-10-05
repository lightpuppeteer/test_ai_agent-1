import * as THREE from 'three';
import { PALETTE, GROUPS, SURFACE } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { Interactable, Anchor, INTERACTION_TYPE, staticRoot } from '../interaction/Interactable.js';
import { sandHeight, sandNormal } from './Terrain.js';
import { BuoyancySystem } from './Buoyancy.js';

const UP = new THREE.Vector3(0, 1, 0);

/**
 * Beach dressing: towels (lie-down anchors) draped on the dunes, parasols
 * that sway in the wind, and floating props (crates, barrels, buoys, a moored
 * rowing boat) driven by the buoyancy system.
 */
export class BeachProps {
  /**
   * @param {object} deps
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} deps.physics
   * @param {import('./TextureFactory.js').TextureFactory} deps.textures
   * @param {BuoyancySystem} deps.buoyancy
   * @param {THREE.Object3D} deps.parent
   */
  constructor({ physics, textures, buoyancy, parent }) {
    this.physics = physics;
    this.textures = textures;
    this.buoyancy = buoyancy;
    this.parent = parent;
    this.interactables = [];
    this.floaters = [];

    const S = createStylizedMaterial;
    this.mat = {
      wood: S({ name: 'BoatWood', color: PALETTE.wood, map: textures.get('wood'), triplanarScale: 0.8 }),
      woodDark: S({ name: 'CrateWood', color: 0x8a6440, map: textures.get('wood'), triplanarScale: 1.0 }),
      paint: S({ name: 'BoatPaint', color: 0x3f7f95, painterly: 0.15 }),
      paintTrim: S({ name: 'BoatTrim', color: PALETTE.carTrim, painterly: 0.1 }),
      buoy: S({ name: 'Buoy', color: 0xd4553a, rim: 0.35 }),
      barrel: S({ name: 'Barrel', color: 0x9a6a3f, map: textures.get('wood'), triplanarScale: 1.2 }),
      iron: S({ name: 'BeachIron', color: PALETTE.ironwork }),
      pole: S({ name: 'ParasolPole', color: 0xe8dfcf }),
    };
    this.parasolMats = [0xd9534f, 0x3f88c5, 0xf2b134, 0xf4eadc].map((c, i) =>
      S({
        name: `Parasol${i}`,
        color: c,
        side: THREE.DoubleSide,
        windSway: 0.12,
        heightGradient: [-0.5, 0.0, 0.0],
        rim: 0.3,
      }),
    );
  }

  build() {
    const towels = [
      [-8, 6, 0.15],
      [-5.5, 7.5, -0.2],
      [9, 4, 0.05],
      [11.5, 5.5, 0.35],
      [-30, 9, -0.1],
      [32, 2, 0.2],
    ];
    towels.forEach(([x, z, yaw], i) => this.towel(x, z, yaw, PALETTE.towels[i % PALETTE.towels.length]));
    this.parasol(-6.8, 4.2);
    this.parasol(10.3, 2.4);
    this.parasol(-31.5, 7.6);

    // Floating props.
    this.rowingBoat(new THREE.Vector3(-14, 0.4, 52), 0.5);
    for (const [x, z] of [
      [-4, 44],
      [6, 50],
      [16, 47],
      [-22, 58],
    ])
      this.crate(new THREE.Vector3(x, 0.6, z));
    this.barrel(new THREE.Vector3(2, 0.5, 58));
    this.barrel(new THREE.Vector3(24, 0.5, 55));
    this.buoy(new THREE.Vector3(-30, 0.3, 66));
    this.buoy(new THREE.Vector3(26, 0.3, 70));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Towels & parasols
  // ---------------------------------------------------------------------------
  /** Towel draped over the sand; lie-down anchor aligned to the surface normal. */
  towel(x, z, yaw, color) {
    const geo = new THREE.PlaneGeometry(1.0, 1.9, 4, 10);
    geo.rotateX(-Math.PI / 2);
    geo.rotateY(yaw);
    geo.translate(x, 0, z);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) pos.setY(i, sandHeight(pos.getX(i), pos.getZ(i)) + 0.025);
    geo.computeVertexNormals();
    const hex = `#${new THREE.Color(color).getHexString()}`;
    const mat = createStylizedMaterial({
      name: 'Towel',
      color: 0xffffff,
      map: this.textures.towel(hex, '#f4eadc'),
      wrap: 0.6,
      painterly: 0.06,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.receiveShadow = true;
    this.parent.add(mesh);

    // Anchor frame: +Y = sand normal, head towards -Z (inland when yaw = 0).
    const n = sandNormal(x, z, new THREE.Vector3());
    const root = staticRoot(new THREE.Vector3(x, sandHeight(x, z), z), yaw);
    const worldQ = alignToNormal(n, yaw);
    const localQ = root.quaternion.clone().invert().multiply(worldQ);
    const anchor = new Anchor({
      id: 'towel',
      position: new THREE.Vector3(0, 0.03, 0),
      quaternion: localQ,
      meta: { standOffset: new THREE.Vector3(0.95, 0, 0.2) },
    });
    this.interactables.push(
      new Interactable({
        type: INTERACTION_TYPE.TOWEL,
        label: 'Lie down',
        object: root,
        anchors: [anchor],
        radius: 1.7,
        center: new THREE.Vector3(0, 0.2, 0),
      }),
    );
  }

  parasol(x, z) {
    const y = sandHeight(x, z);
    const g = new THREE.Group();
    g.position.set(x, y, z);
    g.rotation.z = 0.08;
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 2.4, 6), this.mat.pole);
    pole.position.y = 1.0;
    pole.castShadow = true;
    const canopyGeo = new THREE.ConeGeometry(1.25, 0.45, 10, 1, true).translate(0, -0.22, 0);
    const canopy = new THREE.Mesh(canopyGeo, this.parasolMats[Math.floor(Math.random() * this.parasolMats.length)]);
    canopy.position.y = 2.25;
    canopy.castShadow = true;
    g.add(pole, canopy);
    this.parent.add(g);
    const body = this.physics.createRigidBody(this.physics.RAPIER.RigidBodyDesc.fixed().setTranslation(x, y + 1, z));
    this.physics.createCollider(
      this.physics.RAPIER.ColliderDesc.cylinder(1.2, 0.06).setCollisionGroups(GROUPS.STATIC),
      body,
      { surface: SURFACE.WOOD },
    );
  }

  // ---------------------------------------------------------------------------
  // Floating bodies
  // ---------------------------------------------------------------------------
  _dynamicBody(position, quaternion = null, { linearDamping = 0.05, angularDamping = 0.1 } = {}) {
    const R = this.physics.RAPIER;
    const desc = R.RigidBodyDesc.dynamic()
      .setTranslation(position.x, position.y, position.z)
      .setLinearDamping(linearDamping)
      .setAngularDamping(angularDamping)
      .setCanSleep(true);
    if (quaternion) desc.setRotation({ x: quaternion.x, y: quaternion.y, z: quaternion.z, w: quaternion.w });
    return this.physics.createRigidBody(desc);
  }

  _collider(desc, body, density) {
    desc.setDensity(density).setCollisionGroups(GROUPS.DYNAMIC).setFriction(0.6);
    return this.physics.createCollider(desc, body, { surface: SURFACE.WOOD, owner: 'floater' });
  }

  _addMesh(object, body) {
    object.traverse((o) => {
      if (o.isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
      }
    });
    this.parent.add(object);
    this.physics.link(object, body);
  }

  crate(position) {
    const R = this.physics.RAPIER;
    const size = new THREE.Vector3(0.8, 0.8, 0.8);
    const body = this._dynamicBody(
      position,
      new THREE.Quaternion().setFromEuler(new THREE.Euler(0, Math.random() * 3, 0)),
    );
    this._collider(R.ColliderDesc.cuboid(0.4, 0.4, 0.4), body, 420);
    const g = new THREE.Group();
    const m = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.8, 0.8), this.mat.woodDark);
    const band = new THREE.Mesh(new THREE.BoxGeometry(0.82, 0.1, 0.82), this.mat.wood);
    g.add(m, band);
    this._addMesh(g, body);
    const s = BuoyancySystem.boxSamples(size, 2, 2, 2);
    this.buoyancy.add(body, { ...s, linearDrag: 70, angularDrag: 1.2 });
    this.floaters.push(body);
  }

  barrel(position) {
    const R = this.physics.RAPIER;
    const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(Math.PI / 2, Math.random() * 3, 0));
    const body = this._dynamicBody(position, q);
    this._collider(R.ColliderDesc.cylinder(0.5, 0.33), body, 320);
    const m = new THREE.Mesh(new THREE.CylinderGeometry(0.33, 0.33, 1.0, 14), this.mat.barrel);
    const hoops = new THREE.Mesh(new THREE.CylinderGeometry(0.345, 0.345, 0.06, 14), this.mat.iron);
    hoops.position.y = 0.3;
    const hoops2 = hoops.clone();
    hoops2.position.y = -0.3;
    const g = new THREE.Group();
    g.add(m, hoops, hoops2);
    this._addMesh(g, body);
    // Cylinder ≈ lattice inside its bounding box, volume corrected to πr²h.
    const s = BuoyancySystem.boxSamples(new THREE.Vector3(0.6, 1.0, 0.6), 2, 3, 2);
    this.buoyancy.add(body, { ...s, volume: Math.PI * 0.33 * 0.33 * 1.0, linearDrag: 45, angularDrag: 1.0 });
    this.floaters.push(body);
  }

  buoy(position) {
    const R = this.physics.RAPIER;
    const body = this._dynamicBody(position);
    this._collider(R.ColliderDesc.ball(0.45), body, 140);
    // A ballast weight low down keeps it upright.
    this._collider(R.ColliderDesc.ball(0.1).setTranslation(0, -0.55, 0), body, 6000);
    const g = new THREE.Group();
    g.add(new THREE.Mesh(new THREE.SphereGeometry(0.45, 16, 10), this.mat.buoy));
    const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 1.2, 6), this.mat.iron);
    mast.position.y = 0.9;
    g.add(mast);
    this._addMesh(g, body);
    const s = BuoyancySystem.boxSamples(new THREE.Vector3(0.7, 0.9, 0.7), 2, 3, 2);
    this.buoyancy.add(body, { ...s, volume: (4 / 3) * Math.PI * 0.45 ** 3, linearDrag: 40, angularDrag: 1.5 });
    this._moor(body, new THREE.Vector3(0, -0.6, 0), 4);
    this.floaters.push(body);
  }

  /** Small wooden rowing boat: compound hull, moored with a rope joint. */
  rowingBoat(position, yaw) {
    const R = this.physics.RAPIER;
    const body = this._dynamicBody(position, new THREE.Quaternion().setFromAxisAngle(UP, yaw), {
      linearDamping: 0.1,
      angularDamping: 0.3,
    });
    const L = 3.4;
    const W = 1.35;
    const H = 0.55;
    const t = 0.07;
    const g = new THREE.Group();
    const part = (sx, sy, sz, x, y, z, mat, density = 380) => {
      this._collider(R.ColliderDesc.cuboid(sx / 2, sy / 2, sz / 2).setTranslation(x, y, z), body, density);
      const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), mat);
      m.position.set(x, y, z);
      g.add(m);
    };
    part(W - 0.2, t, L - 0.4, 0, -H / 2 + t / 2, 0, this.mat.wood, 700); // bottom (heavier keel)
    part(t, H, L - 0.3, -W / 2 + t / 2, 0, 0, this.mat.paint); // port
    part(t, H, L - 0.3, W / 2 - t / 2, 0, 0, this.mat.paint); // starboard
    part(W, H, t, 0, 0, -L / 2 + 0.15, this.mat.paint); // stern
    part(W * 0.6, H, t, 0, 0.02, L / 2 - 0.12, this.mat.paint); // bow
    part(W - 0.15, 0.06, 0.3, 0, 0.0, 0.2, this.mat.wood); // thwart
    // Gunwale trim (visual).
    for (const sx of [-1, 1]) {
      const trim = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.05, L - 0.25), this.mat.paintTrim);
      trim.position.set((sx * (W - 0.1)) / 2, H / 2, 0);
      g.add(trim);
    }
    this._addMesh(g, body);
    const s = BuoyancySystem.boxSamples(new THREE.Vector3(W, H, L), 2, 2, 4);
    this.buoyancy.add(body, { ...s, volume: W * H * L * 0.75, linearDrag: 110, angularDrag: 2.0 });
    this._moor(body, new THREE.Vector3(0, -H / 2, L / 2 - 0.2), 6);
    this.floaters.push(body);
  }

  /** Rope joint from a body-local point to the sea floor below it. */
  _moor(body, localAttach, slack) {
    const R = this.physics.RAPIER;
    const p = body.translation();
    const floorY = sandHeight(p.x, p.z);
    const anchor = this.physics.createRigidBody(R.RigidBodyDesc.fixed().setTranslation(p.x, floorY, p.z));
    const length = Math.max(0.5, p.y - floorY) + slack;
    const params = R.JointData.rope(
      length,
      { x: 0, y: 0, z: 0 },
      { x: localAttach.x, y: localAttach.y, z: localAttach.z },
    );
    this.physics.world.createImpulseJoint(params, anchor, body, true);
  }
}

/** Quaternion whose +Y is `normal` and whose forward follows `yaw` projected on the surface. */
export function alignToNormal(normal, yaw, out = new THREE.Quaternion()) {
  const fwd = new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw));
  fwd.addScaledVector(normal, -fwd.dot(normal)).normalize();
  const right = new THREE.Vector3().crossVectors(normal, fwd).normalize();
  const m = new THREE.Matrix4().makeBasis(right, normal, fwd);
  return out.setFromRotationMatrix(m);
}

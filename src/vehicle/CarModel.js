import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { PALETTE } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { enableHeightFog } from '../lighting/ShaderPatches.js';

/**
 * Procedural, soft-edged little classic car (forward = +Z, left = +X).
 * Besides visuals it exposes the interaction rig:
 *   seatMount      Object3D on the driver seat surface (character parent)
 *   seatHeight     seat surface → cabin floor (feet), for the driving pose
 *   doorPivot      hinge of the driver door (animated)
 *   doorAnchor     local pose outside the driver door, at ground level
 *   exitPoints     local ground-level exit candidates, in priority order
 *   wheels         4 wheel Groups (FL, FR, RL, RR) positioned by the vehicle
 */
export class CarModel {
  constructor({ bodyColor = PALETTE.carBody } = {}) {
    const S = createStylizedMaterial;
    const m = {
      body: S({ name: 'CarBody', color: bodyColor, rim: 0.35, painterly: 0.07, wrap: 0.35 }),
      trim: S({ name: 'CarTrim', color: PALETTE.carTrim, rim: 0.3 }),
      dark: S({ name: 'CarDark', color: 0x2a2826 }),
      tire: S({ name: 'Tire', color: 0x2b2a29, rim: 0.15 }),
      seat: S({ name: 'Seat', color: 0x7a4b34 }),
      glass: enableHeightFog(
        new THREE.MeshPhysicalMaterial({
          name: 'CarGlass',
          color: 0xb9d6e0,
          roughness: 0.05,
          metalness: 0,
          transparent: true,
          opacity: 0.25,
          depthWrite: false,
        }),
      ),
      head: new THREE.MeshBasicMaterial({ name: 'Headlight', color: new THREE.Color(2.2, 2.0, 1.6) }),
      tail: new THREE.MeshBasicMaterial({ name: 'Taillight', color: new THREE.Color(1.4, 0.15, 0.1) }),
    };
    this.materials = m;
    this.group = new THREE.Group();
    this.group.name = 'Car';
    const add = (geo, mat, x, y, z, parent = this.group) => {
      const mesh = new THREE.Mesh(geo, mat);
      mesh.position.set(x, y, z);
      mesh.castShadow = mat !== m.glass;
      mesh.receiveShadow = true;
      parent.add(mesh);
      return mesh;
    };

    // Body: lower tub, fenders, bonnet hump, bumpers.
    add(new RoundedBoxGeometry(1.72, 0.58, 3.95, 3, 0.18), m.body, 0, 0, 0);
    for (const [x, z] of [
      [0.83, 1.28],
      [-0.83, 1.28],
      [0.83, -1.22],
      [-0.83, -1.22],
    ])
      add(new RoundedBoxGeometry(0.26, 0.34, 1.0, 2, 0.12), m.body, x, 0.08, z);
    add(new RoundedBoxGeometry(1.4, 0.16, 1.2, 2, 0.08), m.body, 0, 0.3, 1.25);
    add(new RoundedBoxGeometry(1.8, 0.16, 0.18, 2, 0.06), m.trim, 0, -0.14, 2.0);
    add(new RoundedBoxGeometry(1.8, 0.16, 0.18, 2, 0.06), m.trim, 0, -0.14, -2.0);

    // Cabin frame (open glasshouse so the driver stays visible).
    add(new RoundedBoxGeometry(1.5, 0.09, 1.85, 2, 0.04), m.body, 0, 0.94, -0.42);
    for (const [x, z] of [
      [0.7, 0.42],
      [-0.7, 0.42],
      [0.7, -1.28],
      [-0.7, -1.28],
    ])
      add(new THREE.BoxGeometry(0.07, 0.66, 0.07), m.body, x, 0.6, z);
    const shield = add(new THREE.BoxGeometry(1.36, 0.62, 0.02), m.glass, 0, 0.6, 0.48);
    shield.rotation.x = -0.32;
    add(new THREE.BoxGeometry(1.36, 0.56, 0.02), m.glass, 0, 0.6, -1.3);
    add(new THREE.BoxGeometry(0.02, 0.5, 1.6), m.glass, -0.72, 0.6, -0.43);

    // Lights.
    for (const x of [0.58, -0.58]) {
      add(new THREE.SphereGeometry(0.11, 12, 8), m.head, x, 0.1, 1.95);
      add(new THREE.BoxGeometry(0.22, 0.1, 0.04), m.tail, x, 0.08, -1.99);
    }

    // Interior: seats, steering wheel, dashboard.
    add(new RoundedBoxGeometry(0.55, 0.16, 0.55, 2, 0.05), m.seat, 0.38, -0.1, -0.25);
    add(new RoundedBoxGeometry(0.55, 0.6, 0.14, 2, 0.05), m.seat, 0.38, 0.2, -0.55);
    add(new RoundedBoxGeometry(0.55, 0.16, 0.55, 2, 0.05), m.seat, -0.38, -0.1, -0.25);
    add(new RoundedBoxGeometry(0.55, 0.6, 0.14, 2, 0.05), m.seat, -0.38, 0.2, -0.55);
    add(new THREE.BoxGeometry(1.5, 0.18, 0.3), m.dark, 0, 0.33, 0.5);
    this.steeringWheel = add(new THREE.TorusGeometry(0.17, 0.022, 6, 18), m.dark, 0.38, 0.42, 0.28);
    this.steeringWheel.rotation.x = -0.45;

    // Driver door on a hinge at its front edge.
    this.doorPivot = new THREE.Group();
    this.doorPivot.position.set(0.87, 0.0, 0.42);
    this.group.add(this.doorPivot);
    add(new RoundedBoxGeometry(0.07, 0.56, 1.15, 2, 0.03), m.body, 0, 0.02, -0.58, this.doorPivot);
    add(new THREE.BoxGeometry(0.02, 0.5, 1.0), m.glass, -0.02, 0.58, -0.6, this.doorPivot);
    add(new THREE.BoxGeometry(0.03, 0.04, 0.16), m.trim, 0.05, 0.12, -0.95, this.doorPivot);

    // Wheels.
    const tireGeo = new THREE.CylinderGeometry(0.33, 0.33, 0.22, 18).rotateZ(Math.PI / 2);
    const hubGeo = new THREE.CylinderGeometry(0.17, 0.17, 0.235, 12).rotateZ(Math.PI / 2);
    const spokeGeo = new THREE.BoxGeometry(0.24, 0.05, 0.3);
    this.wheels = [];
    for (let i = 0; i < 4; i++) {
      const w = new THREE.Group();
      const spin = new THREE.Group();
      add(tireGeo, m.tire, 0, 0, 0, spin);
      add(hubGeo, m.trim, 0, 0, 0, spin);
      add(spokeGeo, m.dark, 0, 0, 0, spin);
      w.add(spin);
      w.userData.spin = spin;
      this.group.add(w);
      this.wheels.push(w);
    }

    // Interaction rig.
    this.seatHeight = 0.24;
    this.seatMount = new THREE.Object3D();
    this.seatMount.position.set(0.38, -0.02, -0.28);
    this.group.add(this.seatMount);

    const groundY = -0.6;
    this.doorAnchor = {
      position: new THREE.Vector3(1.38, groundY, -0.2),
      quaternion: new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), -Math.PI / 2),
    };
    this.exitPoints = [
      new THREE.Vector3(1.45, groundY, -0.2),
      new THREE.Vector3(1.45, groundY, -1.3),
      new THREE.Vector3(-1.45, groundY, -0.2),
      new THREE.Vector3(0, groundY, -2.75),
      new THREE.Vector3(0, groundY, 2.75),
    ];
    this.doorAngle = 0;
    this.doorTarget = 0;
  }

  /** Door animation: critically damped approach to the target angle. */
  update(dt) {
    this.doorAngle += (this.doorTarget - this.doorAngle) * Math.min(1, dt * 9);
    this.doorPivot.rotation.y = this.doorAngle;
  }
}

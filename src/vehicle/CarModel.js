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
  constructor({ bodyColor = PALETTE.carBody, textures = null } = {}) {
    const S = createStylizedMaterial;
    const set = (n) => textures?.set(n) ?? { map: null, detail: null };
    const tread = set('tread');
    const leather = set('leather');
    const m = {
      // Glossy enamel: low roughness so the sky IBL slides over the curves.
      body: S({
        name: 'CarBody',
        color: bodyColor,
        roughness: 0.32,
        envMapIntensity: 1.25,
        rim: 0.3,
        painterly: 0.05,
        wrap: 0.35,
      }),
      trim: S({ name: 'CarTrim', color: PALETTE.carTrim, roughness: 0.4, rim: 0.3 }),
      chrome: S({
        name: 'Chrome',
        color: 0xdfe3e8,
        metalness: 1,
        roughness: 0.16,
        rim: 0.1,
        painterly: 0,
        envMapIntensity: 1.3,
      }),
      dark: S({ name: 'CarDark', color: 0x2a2826, roughness: 0.7 }),
      rubber: S({ name: 'Rubber', color: 0x1e1e1f, roughness: 0.9, rim: 0.1 }),
      tire: S({
        name: 'Tire',
        color: 0x2b2a29,
        rim: 0.15,
        roughness: 0.92,
        map: tread.map,
        detailMap: tread.detail,
        normalScale: 1.4,
      }),
      sidewall: S({ name: 'TireWall', color: 0x2e2d2c, rim: 0.15, roughness: 0.85 }),
      seat: S({
        name: 'Seat',
        color: 0x7a4b34,
        roughness: 0.6,
        map: leather.map,
        detailMap: leather.detail,
        detailRepeat: [2.5, 2.5],
        normalScale: 1.2,
      }),
      plate: S({ name: 'Plate', color: 0xf1efe8, roughness: 0.5, painterly: 0.02 }),
      amber: new THREE.MeshBasicMaterial({ name: 'Indicator', color: new THREE.Color(1.3, 0.62, 0.12) }),
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

    // Body: lower tub, fenders, bonnet hump, chrome bumpers with overriders.
    add(new RoundedBoxGeometry(1.72, 0.58, 3.95, 3, 0.18), m.body, 0, 0, 0);
    for (const [x, z] of [
      [0.83, 1.28],
      [-0.83, 1.28],
      [0.83, -1.22],
      [-0.83, -1.22],
    ])
      add(new RoundedBoxGeometry(0.26, 0.34, 1.0, 2, 0.12), m.body, x, 0.08, z);
    add(new RoundedBoxGeometry(1.4, 0.16, 1.2, 2, 0.08), m.body, 0, 0.3, 1.25);
    for (const z of [2.0, -2.0]) {
      add(new RoundedBoxGeometry(1.8, 0.14, 0.16, 2, 0.06), m.chrome, 0, -0.14, z);
      for (const x of [0.45, -0.45])
        add(new RoundedBoxGeometry(0.08, 0.26, 0.2, 2, 0.035), m.chrome, x, -0.1, z * 1.01);
    }
    // Chrome waist line + bonnet badge + fuel cap.
    for (const x of [0.865, -0.865]) add(new THREE.BoxGeometry(0.012, 0.018, 3.3), m.chrome, x, 0.16, 0.05);
    add(new THREE.SphereGeometry(0.045, 10, 6), m.chrome, 0, 0.39, 1.84);
    add(new THREE.CylinderGeometry(0.05, 0.05, 0.02, 12).rotateZ(Math.PI / 2), m.chrome, -0.87, 0.18, -1.45);

    // Grille: chrome surround + dark slats between the headlights.
    add(new RoundedBoxGeometry(0.62, 0.24, 0.05, 2, 0.03), m.chrome, 0, 0.07, 1.98);
    add(new THREE.BoxGeometry(0.54, 0.17, 0.02), m.dark, 0, 0.07, 2.0);
    for (let k = 0; k < 7; k++) add(new THREE.BoxGeometry(0.012, 0.17, 0.03), m.chrome, -0.24 + k * 0.08, 0.07, 2.005);

    // Number plates (front and rear) on dark backing.
    for (const [z, y] of [
      [2.09, -0.15],
      [-2.09, 0.02],
    ]) {
      add(new THREE.BoxGeometry(0.52, 0.13, 0.012), m.dark, 0, y, z);
      add(new THREE.BoxGeometry(0.48, 0.1, 0.014), m.plate, 0, y, z + Math.sign(z) * 0.002);
    }

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
    // Wipers resting at the base of the windscreen.
    for (const x of [0.3, -0.3]) {
      const wiper = add(new THREE.BoxGeometry(0.5, 0.012, 0.02), m.dark, x, 0.33, 0.6);
      wiper.rotation.z = x > 0 ? 0.08 : -0.08;
    }
    // Side mirrors on stalks.
    for (const x of [0.86, -0.86]) {
      add(new THREE.CylinderGeometry(0.012, 0.012, 0.12, 6), m.chrome, x, 0.4, 0.48);
      add(new THREE.SphereGeometry(0.065, 12, 8).scale(0.5, 0.75, 1), m.chrome, x + Math.sign(x) * 0.02, 0.48, 0.47);
    }

    // Lights: chrome-ringed headlamps, indicators, tail lamps.
    for (const x of [0.58, -0.58]) {
      add(new THREE.SphereGeometry(0.11, 14, 10), m.head, x, 0.1, 1.95);
      add(new THREE.TorusGeometry(0.115, 0.018, 6, 20), m.chrome, x, 0.1, 2.0);
      add(new THREE.SphereGeometry(0.035, 8, 6), m.amber, x * 1.18, -0.02, 2.0);
      add(new RoundedBoxGeometry(0.24, 0.12, 0.05, 2, 0.02), m.chrome, x, 0.08, -1.985);
      add(new THREE.BoxGeometry(0.2, 0.08, 0.04), m.tail, x, 0.08, -2.0);
    }
    // Exhaust tip.
    add(new THREE.CylinderGeometry(0.035, 0.035, 0.25, 10).rotateX(Math.PI / 2), m.chrome, -0.5, -0.27, -2.0);

    // Interior: seats (leather), steering wheel, dashboard with gauges.
    add(new RoundedBoxGeometry(0.55, 0.16, 0.55, 2, 0.05), m.seat, 0.38, -0.1, -0.25);
    add(new RoundedBoxGeometry(0.55, 0.6, 0.14, 2, 0.05), m.seat, 0.38, 0.2, -0.55);
    add(new RoundedBoxGeometry(0.55, 0.16, 0.55, 2, 0.05), m.seat, -0.38, -0.1, -0.25);
    add(new RoundedBoxGeometry(0.55, 0.6, 0.14, 2, 0.05), m.seat, -0.38, 0.2, -0.55);
    add(new THREE.BoxGeometry(1.5, 0.18, 0.3), m.dark, 0, 0.33, 0.5);
    for (const x of [0.3, 0.46]) {
      const g = add(new THREE.CylinderGeometry(0.05, 0.05, 0.02, 14).rotateX(Math.PI / 2), m.chrome, x, 0.36, 0.35);
      g.rotation.x = -0.4;
    }
    this.steeringWheel = add(new THREE.TorusGeometry(0.17, 0.022, 6, 18), m.dark, 0.38, 0.42, 0.28);
    this.steeringWheel.rotation.x = -0.45;

    // Driver door on a hinge at its front edge.
    this.doorPivot = new THREE.Group();
    this.doorPivot.position.set(0.87, 0.0, 0.42);
    this.group.add(this.doorPivot);
    add(new RoundedBoxGeometry(0.07, 0.56, 1.15, 2, 0.03), m.body, 0, 0.02, -0.58, this.doorPivot);
    add(new THREE.BoxGeometry(0.02, 0.5, 1.0), m.glass, -0.02, 0.58, -0.6, this.doorPivot);
    add(new THREE.BoxGeometry(0.03, 0.04, 0.16), m.chrome, 0.05, 0.12, -0.95, this.doorPivot);
    add(new THREE.BoxGeometry(0.02, 0.014, 1.0), m.chrome, 0.04, 0.29, -0.58, this.doorPivot);

    // Wheels: treaded tyre (tread on the rolling surface, plain sidewalls),
    // painted rim, chrome hubcap with a centre boss.
    const tireGeo = new THREE.CylinderGeometry(0.33, 0.33, 0.22, 28, 1).rotateZ(Math.PI / 2);
    const rimGeo = new THREE.CylinderGeometry(0.2, 0.2, 0.232, 18).rotateZ(Math.PI / 2);
    const capGeo = new THREE.SphereGeometry(0.14, 16, 6, 0, Math.PI * 2, 0, Math.PI / 2.6).rotateZ(-Math.PI / 2);
    const spokeGeo = new THREE.BoxGeometry(0.24, 0.035, 0.3);
    this.wheels = [];
    for (let i = 0; i < 4; i++) {
      const w = new THREE.Group();
      const spin = new THREE.Group();
      const side = i % 2 === 0 ? 1 : -1;
      add(tireGeo, [m.tire, m.sidewall, m.sidewall], 0, 0, 0, spin);
      add(rimGeo, m.trim, 0, 0, 0, spin);
      add(spokeGeo, m.dark, 0, 0, 0, spin);
      const cap = add(capGeo, m.chrome, side * 0.11, 0, 0, spin);
      if (side < 0) cap.rotation.y = Math.PI;
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

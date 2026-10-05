import * as THREE from 'three';
import { GROUPS, SURFACE } from '../config.js';
import { Drivetrain } from './Drivetrain.js';
import { CarModel } from './CarModel.js';
import { Interactable, Anchor, INTERACTION_TYPE } from '../interaction/Interactable.js';

const UP = new THREE.Vector3(0, 1, 0);
const _v = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _up = new THREE.Vector3();
const _axle = new THREE.Vector3();
const _rel = new THREE.Vector3();
const _dr = new THREE.Vector3();
const _imp = new THREE.Vector3();
const _yAxis = new THREE.Vector3(0, 1, 0);
const RAPIER_ROLL_INFLUENCE = 0.1;

/** Wheel layout (chassis space, forward = +Z, left = +X). */
const WHEELS = [
  { name: 'FL', pos: [0.8, -0.05, 1.28], steer: true, drive: false, front: true },
  { name: 'FR', pos: [-0.8, -0.05, 1.28], steer: true, drive: false, front: true },
  { name: 'RL', pos: [0.8, -0.05, -1.22], steer: false, drive: true, front: false },
  { name: 'RR', pos: [-0.8, -0.05, -1.22], steer: false, drive: true, front: false },
];

/**
 * Four-wheel raycast vehicle.
 *
 * Rapier's DynamicRayCastVehicleController (a port of Bullet's raycast
 * vehicle) solves per-wheel ray contacts, spring–damper suspension and the
 * friction-circle tyre model. On top of it this class adds:
 *   - Drivetrain: torque curve, auto gearbox, clutch launch, engine braking
 *   - Brakes with front bias, handbrake that unloads rear lateral grip
 *   - Per-wheel surface grip (stone vs sand) from collider metadata
 *   - Anti-roll bars (load transfer between left/right per axle)
 *   - Aerodynamic drag, rolling resistance, speed-sensitive steering
 */
export class RaycastVehicle {
  /**
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} physics
   * @param {{position: THREE.Vector3, yaw?: number, parent?: THREE.Object3D}} opts
   */
  constructor(physics, { position, yaw = 0, parent = null, config = {} }) {
    this.physics = physics;
    const R = physics.RAPIER;
    this.cfg = {
      mass: 1150,
      centerOfMass: new THREE.Vector3(0, -0.28, 0.08),
      wheelRadius: 0.33,
      suspensionRest: 0.3,
      suspensionTravel: 0.22,
      suspensionStiffness: 32, // Bullet units (× chassis mass)
      dampingCompression: 2.6,
      dampingRelaxation: 3.4,
      maxSuspensionForce: 22000,
      frictionSlip: 1.05, // ≈ peak tyre μ (scaled per surface by SURFACE.grip)
      sideFrictionStiffness: 1.0,
      // Height at which lateral tyre forces act: 1 = contact patch (physical
      // body roll), 0 = CoM height (no roll). Rapier hard-codes Bullet's 0.1.
      rollInfluence: 0.55,
      brakeForce: 9200, // N, all four wheels at full pedal (≈ 0.8 g)
      brakeFrontBias: 0.62,
      handbrakeForce: 3800, // N per rear wheel
      parkingBrakeForce: 2500, // N per wheel when nobody drives
      rollingResistance: 0.015, // × weight
      maxSteer: 0.6,
      minSteerAtSpeed: 0.16, // max steer at 30 m/s
      steerSpeed: 4.5,
      antiRollFront: 9000, // N per metre of compression difference
      antiRollRear: 6000,
      dragArea: 0.78, // Cd·A (m²)
      maxReverseSpeed: 6, // m/s
      ...config,
    };
    const c = this.cfg;

    // --- Chassis rigid body + compound collider ------------------------------
    _q.setFromAxisAngle(UP, yaw);
    this.body = physics.createRigidBody(
      R.RigidBodyDesc.dynamic()
        .setTranslation(position.x, position.y, position.z)
        .setRotation({ x: _q.x, y: _q.y, z: _q.z, w: _q.w })
        .setLinearDamping(0.02)
        .setAngularDamping(0.25)
        .setCcdEnabled(true),
    );
    const L = 3.95;
    const W = 1.72;
    const H = 0.9;
    const inertia = {
      x: (c.mass / 12) * (H * H + L * L),
      y: (c.mass / 12) * (W * W + L * L),
      z: (c.mass / 12) * (W * W + H * H),
    };
    physics.createCollider(
      R.ColliderDesc.cuboid(0.86, 0.29, 1.97)
        .setMassProperties(c.mass, c.centerOfMass, inertia, { x: 0, y: 0, z: 0, w: 1 })
        .setCollisionGroups(GROUPS.VEHICLE)
        .setFriction(0.5),
      this.body,
      { owner: 'vehicle' },
    );
    physics.createCollider(
      R.ColliderDesc.cuboid(0.74, 0.33, 0.95)
        .setTranslation(0, 0.62, -0.42)
        .setDensity(0)
        .setCollisionGroups(GROUPS.VEHICLE)
        .setFriction(0.5),
      this.body,
      { owner: 'vehicle' },
    );

    // --- Raycast vehicle controller -----------------------------------------
    this.controller = physics.world.createVehicleController(this.body);
    physics.trackController(this.controller, 'vehicle');
    this.controller.indexUpAxis = 1;
    this.controller.setIndexForwardAxis = 2; // (sic) Rapier's setter name
    WHEELS.forEach((w, i) => {
      this.controller.addWheel(
        { x: w.pos[0], y: w.pos[1], z: w.pos[2] },
        { x: 0, y: -1, z: 0 },
        { x: -1, y: 0, z: 0 },
        c.suspensionRest,
        c.wheelRadius,
      );
      this.controller.setWheelSuspensionStiffness(i, c.suspensionStiffness);
      this.controller.setWheelSuspensionCompression(i, c.dampingCompression);
      this.controller.setWheelSuspensionRelaxation(i, c.dampingRelaxation);
      this.controller.setWheelMaxSuspensionTravel(i, c.suspensionTravel);
      this.controller.setWheelMaxSuspensionForce(i, c.maxSuspensionForce);
      this.controller.setWheelFrictionSlip(i, c.frictionSlip);
      this.controller.setWheelSideFrictionStiffness(i, c.sideFrictionStiffness);
    });

    this.drivetrain = new Drivetrain({ wheelRadius: c.wheelRadius });

    // --- Visuals ---------------------------------------------------------------
    this.model = new CarModel();
    this.object = this.model.group; // world-space, interpolated by PhysicsWorld
    this.object.position.copy(position);
    this.object.quaternion.copy(_q);
    parent?.add(this.object);
    physics.link(this.object, this.body);

    // --- Controls & telemetry ------------------------------------------------
    this.controls = { throttle: 0, brake: 0, steer: 0, handbrake: false };
    this.steer = 0;
    this.speed = 0;
    this.driver = null;
    this.reservedBy = null;
    this.wheelGrip = new Array(4).fill(1);
    this.wheelSurfaces = new Array(4).fill(null);
  }

  get steerNormalized() {
    return this.steer / this.cfg.maxSteer;
  }

  get rpm() {
    return this.drivetrain.rpm;
  }

  get gearLabel() {
    return this.drivetrain.gearLabel;
  }

  reserve(who) {
    this.reservedBy = who;
  }

  release() {
    this.reservedBy = null;
  }

  setDoorOpen(open) {
    this.model.doorTarget = open ? -1.1 : 0;
  }

  getRenderPosition(out) {
    return out.copy(this.object.position);
  }

  /** World-space exit candidates (ground level), in priority order. */
  getExitCandidates() {
    this.object.updateMatrixWorld(true);
    return this.model.exitPoints.map((p) => p.clone().applyMatrix4(this.object.matrixWorld));
  }

  // ---------------------------------------------------------------------------
  // Physics
  // ---------------------------------------------------------------------------
  fixedUpdate(dt) {
    const c = this.cfg;
    const ctrl = this.controller;
    const body = this.body;
    const { throttle, brake, steer: steerInput, handbrake } = this.controls;
    this.speed = ctrl.currentVehicleSpeed();
    const speed = this.speed;
    const absSpeed = Math.abs(speed);

    // --- Gear selection: brake at standstill engages reverse ----------------
    const dt_ = this.drivetrain;
    let pedalThrottle = throttle;
    let pedalBrake = brake;
    if (dt_.gear === -1) {
      // In reverse, the keys swap roles.
      pedalThrottle = brake;
      pedalBrake = throttle;
      if (throttle > 0.1 && speed > -0.8) dt_.setReverse(false);
    } else if (brake > 0.1 && speed < 0.8 && throttle < 0.1) {
      dt_.setReverse(true);
      pedalThrottle = brake;
      pedalBrake = 0;
    }
    if (!this.driver) pedalThrottle = 0;
    if (dt_.gear === -1 && speed < -c.maxReverseSpeed) pedalThrottle = 0;

    // --- Steering: speed-sensitive limit + rate limiting ---------------------
    const maxSteer = THREE.MathUtils.lerp(c.maxSteer, c.minSteerAtSpeed, Math.min(absSpeed / 30, 1));
    const target = THREE.MathUtils.clamp(steerInput, -1, 1) * maxSteer;
    const rate = c.steerSpeed * dt * (Math.abs(target) < Math.abs(this.steer) ? 1.6 : 1);
    this.steer += THREE.MathUtils.clamp(target - this.steer, -rate, rate);

    // --- Drivetrain → engine force on the driven wheels ---------------------
    const driveForce = dt_.update(dt, speed, pedalThrottle);
    const driven = WHEELS.filter((w) => w.drive).length;

    // --- Per-wheel setup ------------------------------------------------------
    const weightPerWheel = (c.mass * 9.81) / 4;
    WHEELS.forEach((w, i) => {
      ctrl.setWheelSteering(i, w.steer ? this.steer : 0);
      ctrl.setWheelEngineForce(i, w.drive ? driveForce / driven : 0);

      // Surface-dependent grip (sand is loose), handbrake unloads rear lateral grip.
      const surf = this.physics.getColliderInfo(ctrl.wheelGroundObject(i))?.surface ?? SURFACE.STONE;
      this.wheelSurfaces[i] = surf.name;
      const mu = c.frictionSlip * surf.grip;
      ctrl.setWheelFrictionSlip(i, mu);
      ctrl.setWheelSideFrictionStiffness(i, c.sideFrictionStiffness * (handbrake && !w.front ? 0.45 : 1));

      // Brakes in Newtons. Rapier's brake is a per-step impulse limit and is
      // not clamped by tyre grip, so clamp to μ·N ourselves (no super-grip).
      let f = c.rollingResistance * weightPerWheel;
      f += pedalBrake * c.brakeForce * 0.5 * (w.front ? c.brakeFrontBias : 1 - c.brakeFrontBias);
      if (!this.driver) f = Math.max(f, c.parkingBrakeForce);
      if (handbrake && !w.front) f += c.handbrakeForce;
      const load = Math.max(ctrl.wheelSuspensionForce(i) || weightPerWheel, 0);
      f = Math.min(f, mu * load * 1.05 + c.rollingResistance * weightPerWheel);
      ctrl.setWheelBrake(i, f * dt);
    });

    ctrl.updateVehicle(dt, this.physics.RAPIER.QueryFilterFlags.EXCLUDE_SENSORS, GROUPS.QUERY_WHEELS);

    // --- Roll influence + anti-roll bars ----------------------------------------
    this._rollInfluence();
    this._antiRoll(0, 1, c.antiRollFront, dt);
    this._antiRoll(2, 3, c.antiRollRear, dt);

    // --- Aerodynamic drag --------------------------------------------------------
    const lv = body.linvel();
    const v2 = Math.hypot(lv.x, lv.y, lv.z);
    if (v2 > 0.1) {
      const k = -0.5 * 1.225 * c.dragArea * v2 * dt;
      body.applyImpulse({ x: lv.x * k, y: lv.y * k, z: lv.z * k }, true);
    }
  }

  /**
   * Bullet-style `rollInfluence`: the height at which lateral tyre impulses
   * act on the chassis. Rapier applies them at 10% of the contact-patch depth
   * below the CoM (Bullet's default, not exposed in the JS API), which makes
   * cars corner almost flat. We add the torque impulse that moves the point of
   * application to `rollInfluence`, restoring believable body roll and
   * weight transfer while staying well clear of tripping over.
   */
  _rollInfluence() {
    const ctrl = this.controller;
    const k = RAPIER_ROLL_INFLUENCE - this.cfg.rollInfluence;
    if (Math.abs(k) < 1e-3) return;
    const r = this.body.rotation();
    _q.set(r.x, r.y, r.z, r.w);
    const up = _up.set(0, 1, 0).applyQuaternion(_q);
    const com = this.body.worldCom();
    for (let i = 0; i < 4; i++) {
      if (!ctrl.wheelIsInContact(i)) continue;
      const side = ctrl.wheelSideImpulse(i);
      if (!side) continue;
      // World axle of the (steered) wheel.
      _axle
        .set(-1, 0, 0)
        .applyAxisAngle(_yAxis, ctrl.wheelSteering(i) ?? 0)
        .applyQuaternion(_q);
      const cp = ctrl.wheelContactPoint(i);
      _rel.set(cp.x - com.x, cp.y - com.y, cp.z - com.z);
      // Δr = -up·(up·rel)·(0.1 - ri)  →  ΔL = Δr × J
      _dr.copy(up).multiplyScalar(-up.dot(_rel) * k);
      _imp.copy(_axle).multiplyScalar(side);
      _dr.cross(_imp);
      this.body.applyTorqueImpulse({ x: _dr.x, y: _dr.y, z: _dr.z }, true);
    }
  }

  _antiRoll(left, right, stiffness, dt) {
    const ctrl = this.controller;
    const rest = this.cfg.suspensionRest;
    const compL = ctrl.wheelIsInContact(left) ? rest - ctrl.wheelSuspensionLength(left) : 0;
    const compR = ctrl.wheelIsInContact(right) ? rest - ctrl.wheelSuspensionLength(right) : 0;
    const f = (compL - compR) * stiffness * dt;
    if (Math.abs(f) < 1e-4) return;
    const r = this.body.rotation();
    _q.set(r.x, r.y, r.z, r.w);
    const up = _v.set(0, 1, 0).applyQuaternion(_q);
    const pl = ctrl.wheelHardPoint(left);
    const pr = ctrl.wheelHardPoint(right);
    // Compressed side is pushed up, extended side pulled down.
    this.body.applyImpulseAtPoint({ x: up.x * f, y: up.y * f, z: up.z * f }, pl, true);
    this.body.applyImpulseAtPoint({ x: -up.x * f, y: -up.y * f, z: -up.z * f }, pr, true);
  }

  // ---------------------------------------------------------------------------
  // Visuals
  // ---------------------------------------------------------------------------
  update(dt) {
    const ctrl = this.controller;
    WHEELS.forEach((w, i) => {
      const wheel = this.model.wheels[i];
      const susp = ctrl.wheelSuspensionLength(i) ?? this.cfg.suspensionRest;
      wheel.position.set(w.pos[0], w.pos[1] - susp, w.pos[2]);
      wheel.rotation.y = ctrl.wheelSteering(i) ?? 0;
      wheel.userData.spin.rotation.x = ctrl.wheelRotation(i) ?? 0;
    });
    this.model.steeringWheel.rotation.z = -this.steer * 2.5;
    this.model.update(dt);
  }
}

/**
 * Owns all vehicles, registers them as interactables and routes the driver's
 * input (action names) into the active vehicle's controls each fixed step.
 */
export class VehicleSystem {
  constructor({ physics, interactions, parent }) {
    this.physics = physics;
    this.interactions = interactions;
    this.parent = parent;
    this.vehicles = [];
    this.active = null;
    this.inputSource = null;
  }

  spawnCar(position, yaw = 0, config) {
    const v = new RaycastVehicle(this.physics, { position, yaw, parent: this.parent, config });
    const door = new Anchor({
      id: 'driverDoor',
      position: v.model.doorAnchor.position,
      quaternion: v.model.doorAnchor.quaternion,
    });
    v.interactable = this.interactions.register(
      new Interactable({
        type: INTERACTION_TYPE.VEHICLE,
        label: 'Drive',
        object: v.object,
        anchors: [door],
        radius: 3.0,
        center: new THREE.Vector3(0.4, -0.2, 0),
        dynamic: true,
        data: { vehicle: v },
      }),
    );
    this.vehicles.push(v);
    return v;
  }

  /** Routes `input` (an Input instance) to `vehicle`; pass null to release. */
  setDriver(vehicle, input = null) {
    if (this.active && this.active !== vehicle) {
      this.active.driver = null;
      Object.assign(this.active.controls, { throttle: 0, brake: 0, steer: 0, handbrake: true });
    }
    this.active = vehicle;
    this.inputSource = input;
    if (vehicle) vehicle.driver = input ? 'player' : null;
    if (vehicle && !input) {
      vehicle.driver = null;
      Object.assign(vehicle.controls, { throttle: 0, brake: 0, steer: 0, handbrake: true });
      this.active = null;
    }
  }

  fixedUpdate(dt) {
    if (this.active && this.inputSource) {
      const i = this.inputSource;
      const c = this.active.controls;
      c.throttle = i.isDown('forward') ? 1 : 0;
      c.brake = i.isDown('backward') ? 1 : 0;
      c.steer = i.axis('right', 'left'); // +1 = left (positive steering turns left)
      c.handbrake = i.isDown('handbrake');
    }
    for (const v of this.vehicles) v.fixedUpdate(dt);
  }

  update(dt) {
    for (const v of this.vehicles) v.update(dt);
  }
}

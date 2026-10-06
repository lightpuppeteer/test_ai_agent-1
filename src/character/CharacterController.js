import * as THREE from 'three';
import { StateMachine } from './StateMachine.js';
import { CharacterBody, POSTURE } from './CharacterBody.js';
import { CharacterRig } from './CharacterRig.js';
import { Wardrobe } from './Wardrobe.js';
import { CHARACTER } from '../config.js';
import { IdleState, WalkState, RunState, AirborneState } from './states/LocomotionStates.js';
import { SitState, LayDownState } from './states/AnchoredStates.js';
import { EnterVehicleState, DriveState, ExitVehicleState } from './states/VehicleStates.js';
import { INTERACTION_TYPE } from '../interaction/Interactable.js';

/**
 * Allowed FSM transitions. Anything not listed is rejected, which makes the
 * interaction flows explicit and easy to audit.
 */
export const CHARACTER_TRANSITIONS = {
  idle: ['walk', 'run', 'airborne', 'sit', 'layDown', 'enterVehicle'],
  walk: ['idle', 'run', 'airborne', 'sit', 'layDown', 'enterVehicle'],
  run: ['idle', 'walk', 'airborne', 'sit', 'layDown', 'enterVehicle'],
  airborne: ['idle', 'walk', 'run'],
  sit: ['idle'],
  layDown: ['idle'],
  enterVehicle: ['drive', 'idle'],
  drive: ['exitVehicle'],
  exitVehicle: ['idle', 'drive'],
};

/** Interaction type → state that handles it. */
const INTERACTION_STATE = {
  [INTERACTION_TYPE.SEAT]: 'sit',
  [INTERACTION_TYPE.TOWEL]: 'layDown',
  [INTERACTION_TYPE.VEHICLE]: 'enterVehicle',
};

const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _q = new THREE.Quaternion();
const UP = new THREE.Vector3(0, 1, 0);

export const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));

/**
 * The player character: an entity made of components, driven by an FSM.
 *
 *   components
 *   ├─ body      CharacterBody   capsule + Rapier KCC (physics authority on foot)
 *   ├─ rig       CharacterRig    procedural skeleton + pose blending animator
 *   ├─ rig       CharacterRig    animator driving the CharacterMesh skeleton
 *   │              (lofted skinned body, masculine↔feminine morph)
 *   ├─ wardrobe  Wardrobe        garments: skinned shells, Verlet cloth
 *   │              layers, flowing dress, spring hair/scarf
 *   └─ (context) input, interactions, vehicles, camera, hud, environment
 *
 * Each state reads the *intent* (camera-relative move vector, run flag) and
 * uses the helpers below (moveGrounded, walkTo, setRootPose…) so states stay
 * short and declarative. Physics runs in fixedUpdate; presentation in update.
 */
export class CharacterController {
  constructor({ physics, input, interactions, vehicles, environment, cameraRig, hud, parent, camera, spawn }) {
    this.physics = physics;
    this.input = input;
    this.interactions = interactions;
    this.vehicles = vehicles;
    this.environment = environment;
    this.cameraRig = cameraRig;
    this.hud = hud;
    this.parent = parent;
    this.camera = camera;

    // --- Components ---------------------------------------------------------
    const feet = new THREE.Vector3(spawn.x, environment.groundHeightAt(spawn.x, spawn.z) + 0.05, spawn.z);
    this.body = new CharacterBody(physics, feet);
    this.rig = new CharacterRig({ femininity: CHARACTER.femininity });
    parent.add(this.rig.root);
    this.rig.root.position.copy(feet);
    this.yaw = spawn.yaw ?? 0;
    this.rig.root.quaternion.setFromAxisAngle(UP, this.yaw);
    this.rig.update(0);
    this.wardrobe = new Wardrobe({ mesh: this.rig.body, wind: environment.wind, worldParent: parent });
    this.wardrobe.equipOutfit(CHARACTER.outfit);
    this._morph = null; // animated profile change { from, to, t }

    // --- Movement tuning ----------------------------------------------------
    this.walkSpeed = 1.75;
    this.runSpeed = 5.4;
    this.groundAccel = 14;
    this.groundDecel = 20;
    this.airAccel = 3.5;
    this.turnRate = 11; // rad/s

    // --- Runtime state -------------------------------------------------------
    this.intent = { move: new THREE.Vector3(), magnitude: 0, run: false, raw: new THREE.Vector2() };
    this.planarVelocity = new THREE.Vector3();
    this.jumpRequested = false;
    this.rootMode = 'physics'; // 'physics' | 'manual' (anchored / vehicle)
    this._renderQuat = this.rig.root.quaternion.clone();
    this._prevYaw = this.yaw;
    this._turnRate = 0;
    this._prevSpeed = 0;
    this.activeVehicle = null;

    // --- FSM ----------------------------------------------------------------
    this.fsm = new StateMachine(this, CHARACTER_TRANSITIONS);
    this.fsm
      .add(new IdleState())
      .add(new WalkState())
      .add(new RunState())
      .add(new AirborneState())
      .add(new SitState())
      .add(new LayDownState())
      .add(new EnterVehicleState())
      .add(new DriveState())
      .add(new ExitVehicleState());
    this.fsm.onChange((to, from) => this.hud?.setDebugState?.(to, from));
    this.fsm.transition('idle');

    cameraRig.setTarget((out) => this.getCameraTarget(out));
    cameraRig.snapBehind(this.yaw);
  }

  get state() {
    return this.fsm.current?.name;
  }

  // ---------------------------------------------------------------------------
  // Engine hooks
  // ---------------------------------------------------------------------------
  fixedUpdate(dt) {
    this.fsm.fixedUpdate(dt);
  }

  update(dt) {
    this._readIntent();
    if (this.input.consume('toggleProfile')) this.toggleProfile();
    if (this.input.consume('cycleOutfit')) this.cycleOutfit();
    this._updateMorph(dt);
    this.fsm.update(dt);
    this._updatePresentation(dt);

    // Interaction focus only while free to act on foot.
    const feet = this.getFeet(_v);
    if (this.fsm.is('idle', 'walk', 'run')) {
      _v2.set(Math.sin(this.yaw), 0, Math.cos(this.yaw));
      this.interactions.update(feet, _v2);
    } else {
      this.interactions.clearFocus();
    }
    this.environment.setFocus(this.activeVehicle ? this.activeVehicle.getRenderPosition(_v2) : feet);
  }

  lateUpdate(dt) {
    this.rig.root.getWorldPosition(_v);
    this.wardrobe.update(dt, _v.y);
  }

  // ---------------------------------------------------------------------------
  // Intent (input → camera-relative world vector)
  // ---------------------------------------------------------------------------
  _readIntent() {
    const raw = this.input.moveVector(this.intent.raw);
    this.camera.getWorldDirection(_v);
    _v.y = 0;
    if (_v.lengthSq() < 1e-6) _v.set(0, 0, -1);
    _v.normalize();
    _v2.crossVectors(_v, UP); // camera right
    this.intent.move.set(0, 0, 0).addScaledVector(_v, raw.y).addScaledVector(_v2, raw.x);
    this.intent.magnitude = Math.min(1, this.intent.move.length());
    if (this.intent.magnitude > 1e-3) this.intent.move.normalize();
    this.intent.run = this.input.isDown('run');
  }

  /** The locomotion state the current intent asks for. */
  desiredLocomotionState(current) {
    const m = this.intent.magnitude;
    if (m < 0.1) return this.planarVelocity.length() < 0.35 || current === 'idle' ? 'idle' : current;
    return this.intent.run && m > 0.5 ? 'run' : 'walk';
  }

  // ---------------------------------------------------------------------------
  // Movement helpers used by states (fixed step)
  // ---------------------------------------------------------------------------
  /**
   * Accelerates towards the intent velocity and moves the capsule with the KCC.
   * @returns {boolean} whether a jump started
   */
  moveGrounded(dt, { maxSpeed = null, jump = false, air = false } = {}) {
    const speed = maxSpeed ?? (this.intent.run ? this.runSpeed : this.walkSpeed);
    _v.copy(this.intent.move).multiplyScalar(speed * this.intent.magnitude);
    this._accelerate(_v, dt, air);
    if (!air && this.intent.magnitude > 0.05) this._turnTowards(Math.atan2(this.intent.move.x, this.intent.move.z), dt);
    return this.body.move(this.planarVelocity, dt, { jump });
  }

  /** Walks towards a world point (approach phases). Returns remaining distance. */
  walkTo(target, dt, speed = this.walkSpeed) {
    const feet = this.body.getFeet(_v2);
    _v.set(target.x - feet.x, 0, target.z - feet.z);
    const dist = _v.length();
    if (dist > 0.03) {
      _v.multiplyScalar(Math.min(speed, (dist / dt) * 0.5) / dist);
      this._turnTowards(Math.atan2(_v.x, _v.z), dt);
    } else _v.set(0, 0, 0);
    this._accelerate(_v, dt, false);
    this.body.move(this.planarVelocity, dt);
    return dist;
  }

  /** Stands still (keeps gravity/ground snapping) while turning to `yaw`. */
  holdAndFace(dt, yaw) {
    _v.set(0, 0, 0);
    this._accelerate(_v, dt, false);
    this.body.move(this.planarVelocity, dt);
    if (yaw !== undefined) this._turnTowards(yaw, dt);
    return Math.abs(wrapAngle(yaw - this.yaw));
  }

  _accelerate(target, dt, air) {
    const rate = air
      ? this.airAccel
      : target.lengthSq() > this.planarVelocity.lengthSq()
        ? this.groundAccel
        : this.groundDecel;
    _v2.subVectors(target, this.planarVelocity);
    const len = _v2.length();
    const step = rate * dt;
    if (len <= step) this.planarVelocity.copy(target);
    else this.planarVelocity.addScaledVector(_v2, step / len);
  }

  _turnTowards(targetYaw, dt) {
    const d = wrapAngle(targetYaw - this.yaw);
    const step = this.turnRate * dt;
    this.yaw = wrapAngle(this.yaw + THREE.MathUtils.clamp(d, -step, step));
  }

  // ---------------------------------------------------------------------------
  // Presentation
  // ---------------------------------------------------------------------------
  _updatePresentation(dt) {
    const speed = Math.hypot(this.body.velocity.x, this.body.velocity.z);
    this._turnRate = wrapAngle(this.yaw - this._prevYaw) / Math.max(dt, 1e-4);
    this._prevYaw = this.yaw;
    const accel = (speed - this._prevSpeed) / Math.max(dt, 1e-4);
    this._prevSpeed = speed;

    if (this.rootMode === 'physics') {
      this.body.getRenderFeet(this.rig.root.position);
      _q.setFromAxisAngle(UP, this.yaw);
      // Smooth the fixed-step yaw for high refresh rates.
      this._renderQuat.slerp(_q, Math.min(1, dt * 25));
      this.rig.root.quaternion.copy(this._renderQuat);
    }
    this.rig.setLocomotion({
      speed: this.rootMode === 'physics' ? speed : 0,
      grounded: this.rootMode !== 'physics' || this.body.grounded,
      turnRate: this._turnRate,
      accel,
      vy: this.body.verticalVelocity,
    });
    this.rig.update(dt);
  }

  /** Hands the root transform to a state (anchored / vehicle) or back to physics. */
  setRootMode(mode) {
    this.rootMode = mode;
    if (mode === 'physics') this._renderQuat.setFromAxisAngle(UP, this.yaw);
  }

  /** Current feet position (render-space). */
  getFeet(out) {
    return this.rig.root.getWorldPosition(out);
  }

  getCameraTarget(out) {
    if (this.activeVehicle) return this.activeVehicle.getRenderPosition(out).add(_v.set(0, 1.3, 0));
    this.rig.root.getWorldPosition(out);
    const lying = this.rig.poseName === 'lay';
    return out.add(_v.set(0, lying ? 0.7 : this.rig.poseName ? 1.25 : 1.55, 0));
  }

  // ---------------------------------------------------------------------------
  // Interactions
  // ---------------------------------------------------------------------------
  /** Starts the interaction currently in focus (if any). */
  tryInteract() {
    const focus = this.interactions.focus;
    if (!focus) return false;
    const stateName = INTERACTION_STATE[focus.type];
    if (!stateName) return false;
    const anchor = focus.nearestFreeAnchor(this.getFeet(_v));
    if (!anchor) return false;
    return this.fsm.transition(stateName, { interactable: focus, anchor });
  }

  // ---------------------------------------------------------------------------
  // Appearance
  // ---------------------------------------------------------------------------
  /** Smoothly morphs between the masculine and feminine body profiles. */
  toggleProfile(duration = 1.2) {
    const from = this.rig.body.femininity;
    this._morph = { from, to: from >= 0.5 ? 0 : 1, t: 0, duration };
  }

  setProfile(f) {
    this._morph = null;
    this.rig.body.setFemininity(f);
    this.wardrobe.syncProfile();
  }

  _updateMorph(dt) {
    const m = this._morph;
    if (!m) return;
    m.t = Math.min(1, m.t + dt / m.duration);
    const k = m.t * m.t * (3 - 2 * m.t);
    this.rig.body.setFemininity(m.from + (m.to - m.from) * k);
    this.wardrobe.syncProfile();
    if (m.t >= 1) this._morph = null;
  }

  /** Equips the next outfit preset (explorer → skirt & shirt → silver dress → bikini). */
  cycleOutfit() {
    const names = this.wardrobe.outfitNames;
    const next = names[(names.indexOf(this.wardrobe.outfit) + 1) % names.length];
    this.equipOutfit(next);
    return next;
  }

  equipOutfit(name) {
    this.wardrobe.equipOutfit(name);
    this.hud?.toast?.(`Outfit: ${name}`);
  }

  /** Standing capsule centre height (for states that need it). */
  get standingCenterY() {
    return POSTURE.standing.centerY;
  }
}

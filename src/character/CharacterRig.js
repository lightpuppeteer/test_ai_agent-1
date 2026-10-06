import * as THREE from 'three';
import { CharacterMesh } from './CharacterMesh.js';

/**
 * Character animator over the skinned CharacterMesh skeleton.
 *
 * The body is a modular, morphable SkinnedMesh (see CharacterMesh.js); this
 * class only drives its bones. The animator works on a flat pose vector
 * (pelvis offset + Euler per joint):
 *
 *   final = crossfade(snapshot, target)       target = locomotion | static pose
 *   locomotion = idle·w_i + walk·w_w + run·w_r   (weights from actual speed)
 *              → blended with an airborne pose, plus lean from turn/accel
 *
 * Swap-in path for production: keep the same public API (setLocomotion,
 * playPose, update) and drive a GLTF SkinnedMesh with THREE.AnimationMixer
 * (locomotion as a 1D blend space of idle/walk/run clips with synced phase,
 * static poses as cross-faded clips).
 */

const JOINTS = [
  'pelvis',
  'spine',
  'chest',
  'neck',
  'head',
  'upperArmL',
  'foreArmL',
  'handL',
  'upperArmR',
  'foreArmR',
  'handR',
  'thighL',
  'shinL',
  'footL',
  'thighR',
  'shinR',
  'footR',
];
const J = Object.fromEntries(JOINTS.map((n, i) => [n, 3 + i * 3]));
const POSE_SIZE = 3 + JOINTS.length * 3;
const PELVIS_Y = 0.98;

function rot(out, joint, x = 0, y = 0, z = 0) {
  const i = J[joint];
  out[i] = x;
  out[i + 1] = y;
  out[i + 2] = z;
}
function addRot(out, joint, x = 0, y = 0, z = 0) {
  const i = J[joint];
  out[i] += x;
  out[i + 1] += y;
  out[i + 2] += z;
}
/**
 * Body proportions the poses depend on. The procedural body uses the
 * defaults; authored bodies derive them from their skeleton (see CharacterRig).
 *   pelvisY  standing pelvis height
 *   kneelY   pelvis height when kneeling upright (≈ thigh length + 0.12)
 *   armZ     extra arm abduction (negative when the bind pose already spreads the arms)
 */
const DEFAULT_PROPORTIONS = { pelvisY: PELVIS_Y, kneelY: 0.56, armZ: 0 };

function restPose(out, k = DEFAULT_PROPORTIONS) {
  out.fill(0);
  out[1] = k.pelvisY;
  rot(out, 'upperArmL', 0, 0, 0.1 + k.armZ);
  rot(out, 'upperArmR', 0, 0, -0.1 - k.armZ);
  rot(out, 'foreArmL', -0.12);
  rot(out, 'foreArmR', -0.12);
  return out;
}

// ---------------------------------------------------------------------------
// Locomotion cycles (phase φ in radians; one cycle = two steps)
// ---------------------------------------------------------------------------
function idlePose(out, t, k = DEFAULT_PROPORTIONS) {
  restPose(out, k);
  const b = Math.sin(t * 1.6);
  out[1] = k.pelvisY - 0.006 * b;
  rot(out, 'pelvis', 0, 0, 0.025 * Math.sin(t * 0.45));
  rot(out, 'chest', 0.025 * b, 0, -0.02 * Math.sin(t * 0.45));
  rot(out, 'head', 0.03 * Math.sin(t * 0.21), 0.22 * Math.sin(t * 0.31) * Math.sin(t * 0.13), 0);
  rot(out, 'upperArmL', 0.02 * b, 0, 0.1 + k.armZ + 0.015 * b);
  rot(out, 'upperArmR', 0.02 * b, 0, -0.1 - k.armZ - 0.015 * b);
  rot(out, 'thighL', 0, 0, 0.03);
  rot(out, 'thighR', 0, 0, -0.03);
  return out;
}

function walkPose(out, phi, k = DEFAULT_PROPORTIONS) {
  restPose(out, k);
  const s = Math.sin(phi);
  const c = Math.cos(phi);
  out[1] = k.pelvisY - 0.03 * Math.abs(s);
  rot(out, 'pelvis', 0, -0.08 * s, 0.03 * c);
  rot(out, 'spine', 0.04, 0.12 * s, 0);
  rot(out, 'chest', 0, 0.05 * s, -0.03 * c);
  rot(out, 'head', 0, -0.08 * s, 0);
  rot(out, 'thighL', -0.42 * s);
  rot(out, 'thighR', 0.42 * s);
  const kL = 0.08 + 0.62 * Math.max(0, c);
  const kR = 0.08 + 0.62 * Math.max(0, -c);
  rot(out, 'shinL', kL);
  rot(out, 'shinR', kR);
  rot(out, 'footL', 0.42 * s * 0.5 - kL * 0.35);
  rot(out, 'footR', -0.42 * s * 0.5 - kR * 0.35);
  rot(out, 'upperArmL', 0.36 * s, 0, 0.1 + k.armZ);
  rot(out, 'upperArmR', -0.36 * s, 0, -0.1 - k.armZ);
  rot(out, 'foreArmL', -0.25 - 0.2 * Math.max(0, -s));
  rot(out, 'foreArmR', -0.25 - 0.2 * Math.max(0, s));
  return out;
}

function runPose(out, phi, k = DEFAULT_PROPORTIONS) {
  restPose(out, k);
  const s = Math.sin(phi);
  const c = Math.cos(phi);
  out[1] = k.pelvisY - 0.06 + 0.05 * Math.abs(s);
  rot(out, 'pelvis', 0, -0.14 * s, 0.04 * c);
  rot(out, 'spine', 0.2, 0.2 * s, 0);
  rot(out, 'chest', 0.04, 0.08 * s, 0);
  rot(out, 'head', -0.12, -0.12 * s, 0);
  rot(out, 'thighL', -0.9 * s - 0.15);
  rot(out, 'thighR', 0.9 * s - 0.15);
  const kL = 0.35 + 1.35 * Math.max(0, c);
  const kR = 0.35 + 1.35 * Math.max(0, -c);
  rot(out, 'shinL', kL);
  rot(out, 'shinR', kR);
  rot(out, 'footL', 0.3 - kL * 0.25);
  rot(out, 'footR', 0.3 - kR * 0.25);
  rot(out, 'upperArmL', 0.75 * s, 0, 0.16 + k.armZ);
  rot(out, 'upperArmR', -0.75 * s, 0, -0.16 - k.armZ);
  rot(out, 'foreArmL', -1.45);
  rot(out, 'foreArmR', -1.45);
  return out;
}

function airPose(out, t, vy, k = DEFAULT_PROPORTIONS) {
  restPose(out, k);
  const rise = THREE.MathUtils.clamp(vy / 5, -1, 1);
  rot(out, 'spine', 0.1 - 0.1 * rise);
  rot(out, 'thighL', -0.75 + 0.2 * rise);
  rot(out, 'shinL', 1.05);
  rot(out, 'thighR', 0.2);
  rot(out, 'shinR', 0.65 - 0.2 * rise);
  rot(out, 'upperArmL', -0.3, 0, 0.85 + 0.15 * Math.sin(t * 9));
  rot(out, 'upperArmR', -0.1, 0, -0.85 - 0.15 * Math.sin(t * 9 + 1));
  rot(out, 'foreArmL', -0.5);
  rot(out, 'foreArmR', -0.5);
  return out;
}

// ---------------------------------------------------------------------------
// Static poses (anchored interactions). `p` = params, `t` = time.
// ---------------------------------------------------------------------------
const STATIC_POSES = {
  sit(out, t, p, k) {
    restPose(out, k);
    out[1] = (p.seatHeight ?? 0.46) + 0.09;
    const b = Math.sin(t * 1.4);
    rot(out, 'spine', 0.06 + 0.015 * b);
    rot(out, 'chest', 0.02 * b);
    rot(out, 'head', 0.05, 0.25 * Math.sin(t * 0.23) * Math.sin(t * 0.11));
    rot(out, 'thighL', -1.5, 0, 0.08);
    rot(out, 'thighR', -1.5, 0, -0.08);
    rot(out, 'shinL', 1.45);
    rot(out, 'shinR', 1.5);
    rot(out, 'upperArmL', -0.42, 0, 0.12);
    rot(out, 'upperArmR', -0.42, 0, -0.12);
    rot(out, 'foreArmL', -0.85);
    rot(out, 'foreArmR', -0.85);
    return out;
  },
  sitTable(out, t, p, k) {
    STATIC_POSES.sit(out, t, p, k);
    rot(out, 'spine', 0.16);
    rot(out, 'upperArmL', -0.8, 0, 0.15);
    rot(out, 'upperArmR', -0.85, 0, -0.15);
    rot(out, 'foreArmL', -1.15, 0.3);
    rot(out, 'foreArmR', -1.1, -0.3);
    return out;
  },
  kneel(out, t, p, k = DEFAULT_PROPORTIONS) {
    restPose(out, k);
    out[1] = k.kneelY;
    out[2] = -0.05;
    rot(out, 'spine', 0.3);
    rot(out, 'thighL', -0.15, 0, 0.06);
    rot(out, 'thighR', -0.05, 0, -0.06);
    rot(out, 'shinL', 1.62);
    rot(out, 'shinR', 1.62);
    rot(out, 'footL', 0.35);
    rot(out, 'footR', 0.35);
    rot(out, 'upperArmL', -0.45, 0, 0.12);
    rot(out, 'upperArmR', -0.45, 0, -0.12);
    rot(out, 'foreArmL', -0.6);
    rot(out, 'foreArmR', -0.6);
    return out;
  },
  /** On the back, head towards -Z of the anchor, one knee up, an arm behind the head. */
  lay(out, t, p, k) {
    restPose(out, k);
    out[0] = 0;
    out[1] = 0.14;
    out[2] = 0.05;
    const b = Math.sin(t * 1.1);
    rot(out, 'pelvis', -Math.PI / 2);
    rot(out, 'chest', 0.02 * b);
    rot(out, 'neck', 0.22);
    rot(out, 'head', 0.05, 0.12 * Math.sin(t * 0.2));
    rot(out, 'upperArmL', 0.05, 0, 0.32);
    rot(out, 'foreArmL', -0.25);
    rot(out, 'upperArmR', -2.75, 0, -0.35);
    rot(out, 'foreArmR', -1.6);
    rot(out, 'thighL', 0.0, 0, 0.05);
    rot(out, 'shinL', 0.05);
    rot(out, 'thighR', -0.75, 0, -0.06);
    rot(out, 'shinR', 1.35);
    rot(out, 'footL', 0.45);
    rot(out, 'footR', 0.1);
    return out;
  },
  drive(out, t, p, k) {
    restPose(out, k);
    out[1] = (p.seatHeight ?? 0.3) + 0.09;
    const steer = p.steer ?? 0;
    rot(out, 'spine', -0.12);
    rot(out, 'chest', 0.02, steer * 0.12);
    rot(out, 'head', 0.06, steer * 0.25);
    rot(out, 'thighL', -1.25, 0, 0.12);
    rot(out, 'thighR', -1.25, 0, -0.12);
    rot(out, 'shinL', 1.0);
    rot(out, 'shinR', 1.05);
    rot(out, 'upperArmL', -1.05 + steer * 0.3, 0, 0.22);
    rot(out, 'upperArmR', -1.05 - steer * 0.3, 0, -0.22);
    rot(out, 'foreArmL', -0.6);
    rot(out, 'foreArmR', -0.6);
    return out;
  },
};

const smoother = (x) => x * x * x * (x * (x * 6 - 15) + 10);

export class CharacterRig {
  /**
   * @param {object} [o]
   * @param {number} [o.femininity] 0 = masculine … 1 = feminine body profile
   */
  constructor({ femininity = 1, asset = null } = {}) {
    // Skinned body (procedural & morphable, or authored glTF); the animator
    // drives its bones by name.
    this.body = new CharacterMesh({ femininity, asset });
    this.root = this.body.root;
    this.joints = this.body.bones;
    this.proportions = { ...DEFAULT_PROPORTIONS };
    if (this.body.isAuthored) {
      const R = this.body.rest.A;
      this.proportions.pelvisY = R.pelvis.y;
      this.proportions.kneelY = (R.thighL.y - R.shinL.y) + 0.12;
      // The authored bind pose already holds the arms ~0.12 rad from the body.
      this.proportions.armZ = -0.08;
    }

    // Animator state
    this.output = restPose(new Float32Array(POSE_SIZE), this.proportions);
    this.from = new Float32Array(this.output);
    this.target = null; // null = locomotion, else { name, params }
    this.fadeT = 1;
    this.fadeDur = 0.3;
    this._loco = new Float32Array(POSE_SIZE);
    this._tmpA = new Float32Array(POSE_SIZE);
    this._tmpB = new Float32Array(POSE_SIZE);
    this._target = new Float32Array(POSE_SIZE);
    this.phase = 0;
    this.time = 0;
    this.speed = 0;
    this.grounded = true;
    this.airW = 0;
    this.verticalSpeed = 0;
    this.lean = new THREE.Vector2(); // x: forward (accel), y: side (turn)
    this._input = { speed: 0, grounded: true, turnRate: 0, accel: 0, vy: 0 };
    this.walkSpeed = 1.7;
    this.runSpeed = 5.4;
  }

  // ---------------------------------------------------------------------------
  // Animator API
  // ---------------------------------------------------------------------------
  /**
   * Locomotion inputs, updated every frame by the controller.
   * @param {{speed:number, grounded:boolean, turnRate:number, accel:number, vy:number}} p
   */
  setLocomotion(p) {
    Object.assign(this._input, p);
  }

  /**
   * Cross-fades to a static pose (or back to locomotion with `null`).
   * @param {string|null} name one of sit, sitTable, kneel, lay, drive
   * @param {number} fade seconds
   * @param {object} params pose parameters (seatHeight, steer…)
   */
  playPose(name, fade = 0.35, params = {}) {
    this.from.set(this.output);
    this.target = name ? { name, params } : null;
    this.fadeT = fade > 0 ? 0 : 1;
    this.fadeDur = Math.max(fade, 1e-3);
  }

  /** Live update of the current static pose's params (e.g. steering angle). */
  setPoseParams(params) {
    if (this.target) Object.assign(this.target.params, params);
  }

  get poseName() {
    return this.target?.name ?? null;
  }

  update(dt) {
    this.time += dt;
    const inp = this._input;
    // Smooth inputs so state changes never pop.
    this.speed += (inp.speed - this.speed) * Math.min(1, dt * 8);
    this.airW += ((inp.grounded ? 0 : 1) - this.airW) * Math.min(1, dt * (inp.grounded ? 12 : 5));
    this.lean.x += (THREE.MathUtils.clamp(inp.accel * 0.025, -0.15, 0.15) - this.lean.x) * Math.min(1, dt * 6);
    this.lean.y +=
      (THREE.MathUtils.clamp(inp.turnRate * this.speed * 0.03, -0.25, 0.25) - this.lean.y) * Math.min(1, dt * 6);

    this._computeLocomotion(dt);

    // Target pose.
    const tgt = this._target;
    if (this.target) STATIC_POSES[this.target.name](tgt, this.time, this.target.params, this.proportions);
    else tgt.set(this._loco);

    // Cross-fade from the frozen snapshot.
    this.fadeT = Math.min(1, this.fadeT + dt / this.fadeDur);
    const w = smoother(this.fadeT);
    const out = this.output;
    for (let i = 0; i < POSE_SIZE; i++) out[i] = this.from[i] + (tgt[i] - this.from[i]) * w;

    this._apply(out);
  }

  _computeLocomotion(dt) {
    const s = this.speed;
    const ws = this.walkSpeed;
    const rs = this.runSpeed;
    let wi = 0;
    let ww = 0;
    let wr = 0;
    if (s < ws) {
      ww = s / ws;
      wi = 1 - ww;
    } else {
      wr = Math.min(1, (s - ws) / (rs - ws));
      ww = 1 - wr;
    }
    // Stride length grows with speed → cadence stays natural.
    const stride = THREE.MathUtils.lerp(1.25, 2.5, wr);
    if (this._input.grounded) this.phase += (Math.max(s, 0.25 * ww) / stride) * Math.PI * 2 * dt;

    const k = this.proportions;
    const loco = this._loco;
    idlePose(loco, this.time, k);
    for (let i = 0; i < POSE_SIZE; i++) loco[i] *= wi;
    if (ww > 0) {
      walkPose(this._tmpA, this.phase, k);
      for (let i = 0; i < POSE_SIZE; i++) loco[i] += this._tmpA[i] * ww;
    }
    if (wr > 0) {
      runPose(this._tmpB, this.phase, k);
      for (let i = 0; i < POSE_SIZE; i++) loco[i] += this._tmpB[i] * wr;
    }
    if (this.airW > 0.001) {
      airPose(this._tmpA, this.time, this._input.vy, k);
      const a = this.airW;
      for (let i = 0; i < POSE_SIZE; i++) loco[i] = loco[i] * (1 - a) + this._tmpA[i] * a;
    }
    // Lean into acceleration and turns.
    addRot(loco, 'spine', this.lean.x, 0, 0);
    addRot(loco, 'pelvis', 0, 0, -this.lean.y);
    addRot(loco, 'chest', 0, 0, this.lean.y * 0.5);
  }

  _apply(p) {
    const pel = this.joints.pelvis;
    pel.position.set(p[0], p[1], p[2]);
    for (let j = 0; j < JOINTS.length; j++) {
      const i = 3 + j * 3;
      this.joints[JOINTS[j]].rotation.set(p[i], p[i + 1], p[i + 2]);
    }
  }
}

import * as THREE from 'three';
import { State } from '../StateMachine.js';

const UP = new THREE.Vector3(0, 1, 0);
const Z = new THREE.Vector3(0, 0, 1);
const _v = new THREE.Vector3();
const _q = new THREE.Quaternion();
const ease = (t) => t * t * (3 - 2 * t);

/**
 * Root-transform tween used by every anchored transition. While active, the
 * character's root is in 'manual' mode and the physics capsule is either
 * parked on the anchor or (for vehicles) disabled.
 */
export class RootTween {
  constructor() {
    this.fromPos = new THREE.Vector3();
    this.toPos = new THREE.Vector3();
    this.fromQuat = new THREE.Quaternion();
    this.toQuat = new THREE.Quaternion();
    this.t = 1;
    this.duration = 1;
  }

  start(root, toPos, toQuat, duration) {
    this.fromPos.copy(root.position);
    this.fromQuat.copy(root.quaternion);
    this.toPos.copy(toPos);
    this.toQuat.copy(toQuat);
    this.t = 0;
    this.duration = Math.max(duration, 1e-3);
  }

  /** Advances and applies the tween to `root`; returns true when finished. */
  step(root, dt) {
    this.t = Math.min(1, this.t + dt / this.duration);
    const k = ease(this.t);
    root.position.lerpVectors(this.fromPos, this.toPos, k);
    root.quaternion.slerpQuaternions(this.fromQuat, this.toQuat, k);
    return this.t >= 1;
  }
}

const yawQuat = (yaw, out = new THREE.Quaternion()) => out.setFromAxisAngle(UP, yaw);
const yawOf = (q) => {
  _v.copy(Z).applyQuaternion(q);
  return Math.atan2(_v.x, _v.z);
};

/**
 * Base for interactions that snap the character to an anchor matrix.
 * Subclasses define the phase script; this class handles anchor
 * reservation, approach, safe stand-up and cleanup.
 */
class AnchoredState extends State {
  enter(_prev, { interactable, anchor }) {
    const c = this.owner;
    this.interactable = interactable;
    this.anchor = anchor;
    anchor.occupant = c;
    this.anchorPos = new THREE.Vector3();
    this.anchorQuat = new THREE.Quaternion();
    interactable.getAnchorWorld(anchor, this.anchorPos, this.anchorQuat);
    this.standPoint = new THREE.Vector3()
      .copy(anchor.meta.standOffset ?? new THREE.Vector3(0, 0, 0.6))
      .applyQuaternion(this.anchorQuat)
      .add(this.anchorPos);
    this.tween = new RootTween();
    this.waypoints = this._planApproach();
    this.setPhase('approach');
  }

  /**
   * Minimal pathing: if the character is behind the anchor (e.g. behind a
   * bench), first walk around its side, then to the stand point. Anchors are
   * small props, so one side waypoint is enough; a navmesh could replace this.
   */
  _planApproach() {
    const feet = this.owner.body.getFeet(new THREE.Vector3());
    const fwd = new THREE.Vector3(0, 0, 1).applyQuaternion(this.anchorQuat).setY(0).normalize();
    const toFeet = new THREE.Vector3().subVectors(feet, this.anchorPos).setY(0);
    const toStand = new THREE.Vector3().subVectors(this.standPoint, this.anchorPos).setY(0);
    // Behind = on the opposite side of the anchor from its stand point.
    if (toStand.lengthSq() < 1e-4 || toFeet.dot(toStand) > 0) return [this.standPoint];
    const right = new THREE.Vector3().crossVectors(fwd, UP).normalize();
    const side = Math.sign(toFeet.dot(right)) || 1;
    const clearance = (this.anchor.meta.sideClearance ?? 1.25) + 0.35;
    const around = this.standPoint.clone().addScaledVector(right, side * clearance);
    return [around, this.standPoint];
  }

  setPhase(name) {
    this.phase = name;
    this.phaseTime = 0;
    this._fresh = true;
  }

  /** True exactly once after a phase change (robust to several fixed steps per frame). */
  phaseStarted() {
    const f = this._fresh;
    this._fresh = false;
    return f;
  }

  exit() {
    if (this.anchor?.occupant === this.owner) this.anchor.occupant = null;
    this.owner.cameraRig.setMode('follow');
  }

  /** Follows the approach waypoints on foot; returns true when arrived (or timed out). */
  approach(dt) {
    const target = this.waypoints[0];
    const last = this.waypoints.length === 1;
    const d = this.owner.walkTo(target, dt, this.owner.walkSpeed * 1.2);
    if (!last && (d < 0.35 || this.phaseTime > 2.5)) {
      this.waypoints.shift();
      this.phaseTime = 0;
      return false;
    }
    // A blocked approach falls through to the snap tween after a short timeout.
    return d < 0.12 || this.phaseTime > 2.5;
  }

  /** Whether the player asked to leave the anchor. */
  wantsToLeave() {
    const c = this.owner;
    return c.input.consume('interact') || c.input.consume('jump') || (c.intent.magnitude > 0.5 && this.phaseTime > 0.5);
  }

  /** Restores the standing capsule at a free spot near the stand point and hands control back. */
  finishStanding(feetHint, yaw) {
    const c = this.owner;
    const b = c.body;
    b.setPosture('standing');
    const candidates = [feetHint];
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      candidates.push(new THREE.Vector3(feetHint.x + Math.sin(a) * 0.7, feetHint.y, feetHint.z + Math.cos(a) * 0.7));
    }
    const feet = b.findSafeFeetPosition(candidates) ?? feetHint;
    b.teleportFeet(feet);
    c.yaw = yaw;
    c.planarVelocity.set(0, 0, 0);
    c.setRootMode('physics');
    this.machine.transition('idle');
  }

  fixedUpdate(dt) {
    this.phaseTime += dt;
  }
}

/**
 * SIT — approach → turn back to the seat → settle (snap to the anchor matrix
 * with a pose cross-fade) → seated → stand up (safe placement) → idle.
 */
export class SitState extends AnchoredState {
  constructor() {
    super('sit');
  }

  enter(prev, params) {
    super.enter(prev, params);
    this.seatYaw = yawOf(this.anchorQuat);
    this.seatHeight = this.anchor.meta.seatHeight ?? 0.46;
    this.pose = this.anchor.meta.pose ?? 'sit';
  }

  fixedUpdate(dt) {
    super.fixedUpdate(dt);
    const c = this.owner;
    if (this.phase === 'approach') {
      if (this.approach(dt)) this.setPhase('turn');
    } else if (this.phase === 'turn') {
      if (c.holdAndFace(dt, this.seatYaw) < 0.06 || this.phaseTime > 0.6) this.setPhase('settle');
    }
  }

  update(dt) {
    const c = this.owner;
    const root = c.rig.root;
    switch (this.phase) {
      case 'settle': {
        if (this.phaseStarted()) {
          c.setRootMode('manual');
          // Floor point beneath the seat; the pose lifts the pelvis to seat height.
          const floor = _v
            .copy(UP)
            .applyQuaternion(this.anchorQuat)
            .multiplyScalar(-this.seatHeight)
            .add(this.anchorPos);
          const q = yawQuat(this.seatYaw, _q);
          this.tween.start(root, floor, q, 0.65);
          c.rig.playPose(this.pose, 0.65, { seatHeight: this.seatHeight });
          c.body.setPosture('seated');
          c.body.placeAnchored(floor, q);
          c.cameraRig.setMode('anchored');
        }
        if (this.tween.step(root, dt)) this.setPhase('seated');
        break;
      }
      case 'seated':
        if (this.wantsToLeave()) {
          this.setPhase('standUp');
          this.tween.start(root, this.standPoint, yawQuat(this.seatYaw, _q), 0.55);
          c.rig.playPose(null, 0.55);
        }
        break;
      case 'standUp':
        if (this.tween.step(root, dt)) this.finishStanding(this.standPoint, this.seatYaw);
        break;
      default:
        break;
    }
  }
}

/**
 * LAY DOWN — approach the towel side → face it → kneel → roll onto the towel
 * (root aligned to the towel's surface normal, horizontal "lying" capsule
 * oriented along the towel) → lying → kneel → rise → idle.
 */
export class LayDownState extends AnchoredState {
  constructor() {
    super('layDown');
  }

  enter(prev, params) {
    super.enter(prev, params);
    this.kneelPos = new THREE.Vector3();
    this.kneelQuat = new THREE.Quaternion();
  }

  fixedUpdate(dt) {
    super.fixedUpdate(dt);
    const c = this.owner;
    if (this.phase === 'approach') {
      if (this.approach(dt)) this.setPhase('turn');
    } else if (this.phase === 'turn') {
      const feet = c.body.getFeet(_v);
      this.faceYaw = Math.atan2(this.anchorPos.x - feet.x, this.anchorPos.z - feet.z);
      if (c.holdAndFace(dt, this.faceYaw) < 0.08 || this.phaseTime > 0.7) this.setPhase('kneel');
    }
  }

  update(dt) {
    const c = this.owner;
    const root = c.rig.root;
    switch (this.phase) {
      case 'kneel': {
        if (this.phaseStarted()) {
          c.setRootMode('manual');
          this.kneelPos.copy(root.position).lerp(this.anchorPos, 0.3);
          this.kneelPos.y = c.environment.groundHeightAt(this.kneelPos.x, this.kneelPos.z);
          yawQuat(this.faceYaw, this.kneelQuat);
          this.tween.start(root, this.kneelPos, this.kneelQuat, 0.55);
          c.rig.playPose('kneel', 0.55);
          c.cameraRig.setMode('anchored');
        }
        if (this.tween.step(root, dt)) {
          this.setPhase('lie');
          this.tween.start(root, this.anchorPos, this.anchorQuat, 1.0);
          c.rig.playPose('lay', 1.0);
          // Horizontal capsule aligned with the towel and its surface normal.
          c.body.setPosture('lying');
          c.body.placeAnchored(this.anchorPos, this.anchorQuat);
        }
        break;
      }
      case 'lie':
        if (this.tween.step(root, dt)) this.setPhase('lying');
        break;
      case 'lying':
        if (this.wantsToLeave()) {
          this.setPhase('getUp');
          this.tween.start(root, this.kneelPos, this.kneelQuat, 0.8);
          c.rig.playPose('kneel', 0.8);
        }
        break;
      case 'getUp':
        if (this.tween.step(root, dt)) {
          this.setPhase('rise');
          this.tween.start(root, this.standPoint, this.kneelQuat, 0.5);
          c.rig.playPose(null, 0.5);
        }
        break;
      case 'rise':
        if (this.tween.step(root, dt)) this.finishStanding(this.standPoint, this.faceYaw);
        break;
      default:
        break;
    }
  }
}

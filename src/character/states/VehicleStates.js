import * as THREE from 'three';
import { State } from '../StateMachine.js';
import { RootTween } from './AnchoredStates.js';

const UP = new THREE.Vector3(0, 1, 0);
const Z = new THREE.Vector3(0, 0, 1);
const _v = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _pos = new THREE.Vector3();
const _quat = new THREE.Quaternion();

/**
 * ENTER VEHICLE
 *   approach  walk (KCC) to the door anchor; snaps if blocked for too long
 *   open      face the car, door swings open
 *   getIn     capsule disabled, rig re-parented to the seat mount
 *             (Object3D.attach keeps the world transform), then tweened
 *             into the seat while cross-fading to the driving pose
 *   → DRIVE
 */
export class EnterVehicleState extends State {
  constructor() {
    super('enterVehicle');
  }

  enter(_prev, { interactable, anchor }) {
    this.interactable = interactable;
    this.anchor = anchor;
    this.vehicle = interactable.data.vehicle;
    anchor.occupant = this.owner;
    this.phase = 'approach';
    this.phaseTime = 0;
    this._fresh = true;
    this.tween = new RootTween();
    this.doorPos = new THREE.Vector3();
    this.doorQuat = new THREE.Quaternion();
    this.vehicle.reserve(this.owner);
  }

  _setPhase(p) {
    this.phase = p;
    this.phaseTime = 0;
    this._fresh = true;
  }

  fixedUpdate(dt) {
    const c = this.owner;
    this.phaseTime += dt;
    this.interactable.getAnchorWorld(this.anchor, this.doorPos, this.doorQuat);
    if (this.phase === 'approach') {
      const d = c.walkTo(this.doorPos, dt, c.walkSpeed * 1.3);
      if (d < 0.15 || this.phaseTime > 3.5) this._setPhase('open');
    } else if (this.phase === 'open') {
      _v.copy(Z).applyQuaternion(this.doorQuat);
      c.holdAndFace(dt, Math.atan2(_v.x, _v.z));
    }
  }

  update(dt) {
    const c = this.owner;
    const v = this.vehicle;
    if (this.phase === 'open') {
      if (this._fresh) {
        this._fresh = false;
        v.setDoorOpen(true);
      }
      if (this.phaseTime > 0.45) this._setPhase('getIn');
    } else if (this.phase === 'getIn') {
      const root = c.rig.root;
      if (this._fresh) {
        this._fresh = false;
        c.body.setEnabled(false);
        c.setRootMode('manual');
        c.activeVehicle = v;
        v.model.seatMount.attach(root); // keeps world transform
        _pos.set(0, -v.model.seatHeight, 0);
        this.tween.start(root, _pos, _q.identity(), 0.85);
        c.rig.playPose('drive', 0.85, { seatHeight: v.model.seatHeight, steer: 0 });
        c.cameraRig.setMode('vehicle');
      }
      this.phaseTime += dt;
      if (this.tween.step(root, dt)) {
        v.setDoorOpen(false);
        this.machine.transition('drive', { interactable: this.interactable, anchor: this.anchor });
      }
    }
  }
}

/**
 * DRIVE — keyboard input is routed to the vehicle through VehicleSystem;
 * the rig only mirrors steering. Exiting requires a near-standstill.
 */
export class DriveState extends State {
  constructor() {
    super('drive');
  }

  enter(_prev, { interactable, anchor }) {
    const c = this.owner;
    this.interactable = interactable;
    this.anchor = anchor;
    this.vehicle = interactable.data.vehicle;
    c.activeVehicle = this.vehicle;
    c.input.flush('interact', 'jump');
    c.vehicles.setDriver(this.vehicle, c.input);
    c.cameraRig.setMode('vehicle');
    c.hud?.showVehicle(this.vehicle);
  }

  exit() {
    this.owner.hud?.hideVehicle();
  }

  update() {
    const c = this.owner;
    c.rig.setPoseParams({ steer: this.vehicle.steerNormalized });
    if (c.input.consume('interact')) {
      if (Math.abs(this.vehicle.speed) < 2.5) {
        this.machine.transition('exitVehicle', { interactable: this.interactable, anchor: this.anchor });
      } else {
        c.hud?.toast('Slow down to get out');
      }
    }
  }
}

/**
 * EXIT VEHICLE
 *   door      inputs cut, handbrake on, door opens
 *   findSpot  candidate exit points (driver door, passenger door, rear, front)
 *             are ground-probed and capsule-tested; none free → back to DRIVE
 *   getOut    rig detached back to the world, tweened to the spot
 *   finish    capsule re-enabled at the spot (safe spawn), door closes → IDLE
 */
export class ExitVehicleState extends State {
  constructor() {
    super('exitVehicle');
  }

  enter(_prev, { interactable, anchor }) {
    const c = this.owner;
    this.interactable = interactable;
    this.anchor = anchor;
    this.vehicle = interactable.data.vehicle;
    c.vehicles.setDriver(null);
    this.vehicle.setDoorOpen(true);
    this.phase = 'door';
    this.phaseTime = 0;
    this.tween = new RootTween();
  }

  update(dt) {
    const c = this.owner;
    const v = this.vehicle;
    this.phaseTime += dt;
    if (this.phase === 'door' && this.phaseTime > 0.4) {
      const candidates = v.getExitCandidates();
      const feet = c.body.findSafeFeetPosition(candidates);
      if (!feet) {
        c.hud?.toast('No room to get out');
        v.setDoorOpen(false);
        this.machine.transition('drive', { interactable: this.interactable, anchor: this.anchor });
        return;
      }
      this.feet = feet;
      // Face away from the car.
      v.getRenderPosition(_v);
      this.exitYaw = Math.atan2(feet.x - _v.x, feet.z - _v.z);
      const root = c.rig.root;
      c.parent.attach(root); // back to world space, same world transform
      root.getWorldQuaternion(_quat);
      root.quaternion.copy(_quat);
      this.tween.start(root, feet, _q.setFromAxisAngle(UP, this.exitYaw), 0.7);
      c.rig.playPose(null, 0.7);
      this.phase = 'getOut';
      this.phaseTime = 0;
    } else if (this.phase === 'getOut') {
      if (this.tween.step(c.rig.root, dt)) {
        c.body.setPosture('standing');
        c.body.setEnabled(true);
        c.body.teleportFeet(this.feet);
        c.yaw = this.exitYaw;
        c.planarVelocity.set(0, 0, 0);
        c.setRootMode('physics');
        c.activeVehicle = null;
        v.setDoorOpen(false);
        v.release();
        this.anchor.occupant = null;
        c.cameraRig.snapBehind(this.exitYaw, 0.6);
        this.machine.transition('idle');
      }
    }
  }
}

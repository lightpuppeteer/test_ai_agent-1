import * as THREE from 'three';
import { GROUPS } from '../config.js';

const _target = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _desired = new THREE.Vector3();

/** Per-mode framing. Distances in metres, pitch in radians. */
const MODES = {
  follow: { distance: 5.2, min: 2.2, max: 10, pitch: 0.28, followLag: 12, fov: 55 },
  anchored: { distance: 3.8, min: 1.8, max: 7, pitch: 0.32, followLag: 4, fov: 50 },
  vehicle: { distance: 7.5, min: 4.5, max: 14, pitch: 0.2, followLag: 9, fov: 60, autoAlign: true },
};

/**
 * Third-person orbit camera with:
 *  - mouse-drag orbit + wheel zoom, per-mode framing (follow / anchored / vehicle)
 *  - frame-rate independent smoothing of the focus point
 *  - vehicle mode auto-aligns behind the direction of travel when idle
 *  - collision: sphere-ish ray cast against static geometry only (fast in,
 *    slow out) so walls never come between the player and the camera
 */
export class CameraRig {
  constructor(camera, input, physics) {
    this.camera = camera;
    this.input = input;
    this.physics = physics;
    this.mode = 'follow';
    this.cfg = MODES.follow;
    this.yaw = 0;
    this.pitch = MODES.follow.pitch;
    this.distance = MODES.follow.distance;
    this.userDistance = { ...Object.fromEntries(Object.entries(MODES).map(([k, v]) => [k, v.distance])) };
    this.currentDistance = this.distance;
    this.focus = new THREE.Vector3();
    this._targetFn = null;
    this._initialised = false;
    this._prevTarget = new THREE.Vector3();
    this._look = new THREE.Vector2();
  }

  setTarget(fn) {
    this._targetFn = fn;
  }

  setMode(mode) {
    if (this.mode === mode) return;
    this.mode = mode;
    this.cfg = MODES[mode];
  }

  /** Places the camera behind a heading (yaw of the character/vehicle). */
  snapBehind(headingYaw, blend = 1) {
    const target = headingYaw + Math.PI;
    const d = Math.atan2(Math.sin(target - this.yaw), Math.cos(target - this.yaw));
    this.yaw += d * blend;
  }

  lateUpdate(dt) {
    if (!this._targetFn) return;
    const cfg = this.cfg;
    this._targetFn(_target);

    // --- Input -------------------------------------------------------------
    const look = this.input.consumeLook(this._look);
    this.yaw -= look.x * 0.0055;
    this.pitch = THREE.MathUtils.clamp(this.pitch + look.y * 0.004, -0.35, 1.25);
    const zoom = this.input.consumeZoom();
    if (zoom) {
      const d = this.userDistance[this.mode] * (1 + zoom * 0.12);
      this.userDistance[this.mode] = THREE.MathUtils.clamp(d, cfg.min, cfg.max);
    }

    // --- Vehicle: swing behind the direction of travel when not orbiting ---
    if (cfg.autoAlign && performance.now() - this.input.lastLookTime > 1500) {
      _dir.subVectors(_target, this._prevTarget).setY(0);
      if (_dir.lengthSq() > (2.0 * dt) ** 2) {
        const heading = Math.atan2(_dir.x, _dir.z);
        const want = heading + Math.PI;
        const d = Math.atan2(Math.sin(want - this.yaw), Math.cos(want - this.yaw));
        this.yaw += d * Math.min(1, dt * 2.2);
        this.pitch += (cfg.pitch - this.pitch) * Math.min(1, dt * 1.5);
      }
    }
    this._prevTarget.copy(_target);

    // --- Focus smoothing ----------------------------------------------------------
    if (!this._initialised) {
      this.focus.copy(_target);
      this._initialised = true;
    } else {
      this.focus.lerp(_target, 1 - Math.exp(-cfg.followLag * dt));
    }

    // --- Desired position -------------------------------------------------------------
    const want = this.userDistance[this.mode];
    this.distance += (want - this.distance) * Math.min(1, dt * 4);
    _dir.set(
      Math.sin(this.yaw) * Math.cos(this.pitch),
      Math.sin(this.pitch),
      Math.cos(this.yaw) * Math.cos(this.pitch),
    );

    // --- Collision ---------------------------------------------------------------------
    let allowed = this.distance;
    const hit = this.physics.raycast(this.focus, _dir, this.distance + 0.3, GROUPS.QUERY_CAMERA);
    if (hit) allowed = Math.max(0.6, hit.distance - 0.3);
    // Pull in instantly, ease back out.
    if (allowed < this.currentDistance) this.currentDistance = allowed;
    else this.currentDistance += (allowed - this.currentDistance) * Math.min(1, dt * 3);

    _desired.copy(this.focus).addScaledVector(_dir, this.currentDistance);
    this.camera.position.copy(_desired);
    this.camera.lookAt(this.focus);

    if (Math.abs(this.camera.fov - cfg.fov) > 0.01) {
      this.camera.fov += (cfg.fov - this.camera.fov) * Math.min(1, dt * 3);
      this.camera.updateProjectionMatrix();
    }
  }
}

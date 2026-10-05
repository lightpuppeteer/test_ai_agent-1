import * as THREE from 'three';
import { GROUPS, PHYSICS } from '../config.js';

/**
 * Capsule postures. `centerY` = capsule centre height above the feet / anchor
 * when upright. Lying uses a horizontal capsule (see placeAnchored).
 */
export const POSTURE = {
  standing: { halfHeight: 0.55, radius: 0.32, centerY: 0.88 },
  seated: { halfHeight: 0.22, radius: 0.28, centerY: 0.62 },
  lying: { halfHeight: 0.62, radius: 0.2, centerY: 0.2 },
};

const _q = new THREE.Quaternion();
const _v = new THREE.Vector3();
const X_AXIS = new THREE.Vector3(1, 0, 0);

/**
 * Physics bridge for the character: a kinematic capsule moved by Rapier's
 * KinematicCharacterController (slopes, steps, snapping, pushing props).
 *
 * The capsule is the *authority* for where the character is while on foot.
 * Anchored states (sit, lie) place it kinematically on the anchor with a
 * posture-specific shape; vehicle states disable it entirely.
 */
export class CharacterBody {
  /**
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} physics
   * @param {THREE.Vector3} feetPosition
   */
  constructor(physics, feetPosition) {
    this.physics = physics;
    const R = physics.RAPIER;
    this.posture = 'standing';
    const P = POSTURE.standing;

    this.body = physics.createRigidBody(
      R.RigidBodyDesc.kinematicPositionBased().setTranslation(
        feetPosition.x,
        feetPosition.y + P.centerY,
        feetPosition.z,
      ),
    );
    this.collider = this._createCollider(P);

    // Kinematic character controller.
    this.controller = physics.world.createCharacterController(0.02);
    physics.trackController(this.controller, 'character');
    const c = this.controller;
    c.setUp({ x: 0, y: 1, z: 0 });
    c.setMaxSlopeClimbAngle(THREE.MathUtils.degToRad(48));
    c.setMinSlopeSlideAngle(THREE.MathUtils.degToRad(40));
    c.enableAutostep(0.38, 0.18, false);
    c.enableSnapToGround(0.45);
    c.setSlideEnabled(true);
    c.setApplyImpulsesToDynamicBodies(true);
    c.setCharacterMass(75);

    // Render proxy: interpolated by PhysicsWorld between fixed steps.
    this.proxy = new THREE.Object3D();
    this.link = physics.link(this.proxy, this.body);

    this.verticalVelocity = 0;
    this.grounded = false;
    this.groundedTime = 0;
    this.airTime = 0;
    this.velocity = new THREE.Vector3(); // actual (post-collision) velocity
    this.groundNormal = new THREE.Vector3(0, 1, 0);
    this.enabled = true;
    this.jumpSpeed = 5.2;
  }

  _createCollider(p) {
    const R = this.physics.RAPIER;
    const desc = R.ColliderDesc.capsule(p.halfHeight, p.radius)
      .setCollisionGroups(GROUPS.CHARACTER)
      .setFriction(0)
      .setDensity(0);
    return this.physics.createCollider(desc, this.body, { owner: 'character' });
  }

  get capsule() {
    return POSTURE[this.posture];
  }

  /** Current physics feet position (not interpolated). */
  getFeet(out) {
    const t = this.body.translation();
    if (this.posture === 'standing') return out.set(t.x, t.y - POSTURE.standing.centerY, t.z);
    return out.set(t.x, t.y, t.z);
  }

  /** Interpolated feet position for rendering. */
  getRenderFeet(out) {
    return out.copy(this.proxy.position).setY(this.proxy.position.y - POSTURE.standing.centerY);
  }

  /**
   * Moves the standing capsule with the KCC.
   * @param {THREE.Vector3} horizontalVelocity desired XZ velocity (m/s)
   * @param {number} dt
   * @param {{jump?: boolean}} [opts]
   * @returns {boolean} true if a jump started this step
   */
  move(horizontalVelocity, dt, { jump = false } = {}) {
    if (!this.enabled || this.posture !== 'standing') return false;
    let jumped = false;
    if (this.grounded && this.verticalVelocity <= 0) this.verticalVelocity = -1.0; // keep contact on slopes
    this.verticalVelocity += PHYSICS.gravity * dt;
    if (jump && (this.grounded || this.airTime < 0.12)) {
      this.verticalVelocity = this.jumpSpeed;
      jumped = true;
    }
    this.verticalVelocity = Math.max(this.verticalVelocity, -40);

    const desired = {
      x: horizontalVelocity.x * dt,
      y: this.verticalVelocity * dt,
      z: horizontalVelocity.z * dt,
    };
    this.controller.computeColliderMovement(
      this.collider,
      desired,
      this.physics.RAPIER.QueryFilterFlags.EXCLUDE_SENSORS,
      GROUPS.QUERY_CHARACTER,
    );
    const m = this.controller.computedMovement();
    const wasGrounded = this.grounded;
    this.grounded = this.controller.computedGrounded() && !jumped;
    if (this.grounded && this.verticalVelocity < 0) this.verticalVelocity = 0;
    if (!this.grounded && desired.y > 0 && m.y < desired.y * 0.5) this.verticalVelocity = 0; // ceiling

    // Ground normal from the KCC collisions (for slope-aware animation).
    this.groundNormal.set(0, 1, 0);
    for (let i = 0; i < this.controller.numComputedCollisions(); i++) {
      const c = this.controller.computedCollision(i);
      if (c && c.normal1.y > 0.5) this.groundNormal.set(c.normal1.x, c.normal1.y, c.normal1.z);
    }

    const t = this.body.translation();
    this.body.setNextKinematicTranslation({ x: t.x + m.x, y: t.y + m.y, z: t.z + m.z });
    this.velocity.set(m.x / dt, m.y / dt, m.z / dt);

    if (this.grounded) {
      this.groundedTime += dt;
      this.airTime = 0;
    } else {
      this.airTime += dt;
      this.groundedTime = 0;
    }
    if (!wasGrounded && this.grounded) this.landedSpeed = -desired.y / dt;
    return jumped;
  }

  /** Switches collider shape (recreated: cheap, and robust across Rapier versions). */
  setPosture(name) {
    if (this.posture === name) return;
    this.physics.world.removeCollider(this.collider, false);
    this.posture = name;
    this.collider = this._createCollider(POSTURE[name]);
    this.collider.setEnabled(this.enabled);
  }

  /**
   * Places the (non-standing) capsule on an anchor.
   *  - seated: upright capsule above the seat.
   *  - lying:  capsule axis along the anchor's Z, lifted along its normal.
   */
  placeAnchored(anchorPos, anchorQuat) {
    const p = POSTURE[this.posture];
    _v.set(0, p.centerY, 0).applyQuaternion(anchorQuat).add(anchorPos);
    if (this.posture === 'lying') _q.copy(anchorQuat).multiply(_tmpQ.setFromAxisAngle(X_AXIS, Math.PI / 2));
    else _q.identity();
    this.body.setNextKinematicTranslation({ x: _v.x, y: _v.y, z: _v.z });
    this.body.setNextKinematicRotation({ x: _q.x, y: _q.y, z: _q.z, w: _q.w });
    this.velocity.set(0, 0, 0);
    this.verticalVelocity = 0;
  }

  /** Teleports the standing capsule so its feet are at `feet`. */
  teleportFeet(feet) {
    const y = feet.y + POSTURE.standing.centerY;
    this.body.setTranslation({ x: feet.x, y, z: feet.z }, true);
    this.body.setNextKinematicTranslation({ x: feet.x, y, z: feet.z });
    this.body.setRotation({ x: 0, y: 0, z: 0, w: 1 }, true);
    this.body.setNextKinematicRotation({ x: 0, y: 0, z: 0, w: 1 });
    this.physics.resetInterpolation(this.body);
    this.verticalVelocity = 0;
    this.velocity.set(0, 0, 0);
    this.grounded = true;
    this.airTime = 0;
  }

  /** Enables/disables the capsule (vehicles). Disabled bodies are invisible to queries. */
  setEnabled(enabled) {
    this.enabled = enabled;
    this.body.setEnabled(enabled);
    this.link.enabled = enabled;
  }

  /**
   * Returns the first candidate feet position where a standing capsule fits
   * on solid ground, or null. Each candidate is snapped down onto the ground.
   * @param {THREE.Vector3[]} candidates
   */
  findSafeFeetPosition(candidates) {
    const P = POSTURE.standing;
    for (const c of candidates) {
      const hit = this.physics.raycast(
        { x: c.x, y: c.y + 1.6, z: c.z },
        { x: 0, y: -1, z: 0 },
        4,
        GROUPS.QUERY_SPAWN,
        this.body,
      );
      if (!hit || hit.normal.y < 0.6) continue;
      const centre = { x: c.x, y: hit.point.y + P.centerY + 0.04, z: c.z };
      if (this.physics.isCapsuleFree(centre, P.halfHeight, P.radius, GROUPS.QUERY_SPAWN, this.body)) {
        return new THREE.Vector3(c.x, hit.point.y + 0.02, c.z);
      }
    }
    return null;
  }
}

const _tmpQ = new THREE.Quaternion();

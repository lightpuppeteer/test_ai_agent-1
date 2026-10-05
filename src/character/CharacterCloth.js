import * as THREE from 'three';
import { PALETTE } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { VerletCloth } from '../simulation/VerletCloth.js';
import { SpringBoneChain, createSpringTail } from '../simulation/SpringBoneChain.js';

const _p = new THREE.Vector3();
const _a = new THREE.Vector3();
const _b = new THREE.Vector3();

/**
 * Secondary motion component: a Verlet cloak pinned across the shoulders and
 * spring-bone chains for a ponytail and a scarf tail. All of it reacts to the
 * global wind field and to the character's own motion.
 */
export class CharacterCloth {
  /**
   * @param {import('./CharacterRig.js').CharacterRig} rig
   * @param {import('../environment/WindSystem.js').WindSystem} wind
   * @param {THREE.Object3D} worldParent cloth mesh lives in world space
   */
  constructor(rig, wind, worldParent) {
    this.rig = rig;
    this.wind = wind;
    this.windAt = (p, out) => wind.sample(p, out, 0.55);
    this.cols = 9;
    this.rows = 11;
    this._lastChest = new THREE.Vector3();

    rig.root.updateMatrixWorld(true);
    const material = createStylizedMaterial({
      name: 'Cloak',
      color: PALETTE.cloak,
      side: THREE.DoubleSide,
      wrap: 0.6,
      rim: 0.35,
      painterly: 0.14,
      painterlyScale: 1.2,
    });
    this.cloak = new VerletCloth({
      cols: this.cols,
      rows: this.rows,
      initial: (i, j, out) => this._restPoint(i, j, out),
      isPinned: (_i, j) => j === 0,
      material,
      mass: 0.03, // ≈ 3 kg wool cloak
      iterations: 7,
      drag: 0.55,
    });
    worldParent.add(this.cloak.mesh);

    // Torso, thighs, shins as capsule colliders (updated per frame).
    this.capsules = {
      torso: { a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0.19 },
      thighL: { a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0.095 },
      thighR: { a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0.095 },
      shinL: { a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0.075 },
      shinR: { a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0.075 },
    };
    this.cloak.capsules = Object.values(this.capsules);

    // Ponytail from the back of the head, angled back.
    const hairHolder = new THREE.Group();
    hairHolder.position.set(0, 0.17, -0.1);
    hairHolder.rotation.x = 0.9;
    rig.joints.head.add(hairHolder);
    const ponytail = createSpringTail({
      holder: hairHolder,
      segments: 5,
      length: 0.42,
      radiusTop: 0.045,
      radiusBottom: 0.012,
      material: rig.materials.hair,
    });
    this.hair = new SpringBoneChain(ponytail.bones, {
      stiffness: 0.9,
      drag: 0.32,
      gravityPower: 0.45,
      windInfluence: 0.09,
      tipOffset: new THREE.Vector3(0, -0.084, 0),
    });

    // Scarf tail fluttering from the collar.
    const scarfHolder = new THREE.Group();
    scarfHolder.position.set(0.06, 0.05, -0.1);
    scarfHolder.rotation.set(0.5, 0, 0.15);
    rig.joints.chest.add(scarfHolder);
    const scarf = createSpringTail({
      holder: scarfHolder,
      segments: 6,
      length: 0.55,
      radiusTop: 0.05,
      radiusBottom: 0.035,
      flatten: 0.25,
      material: rig.materials.scarf,
    });
    this.scarf = new SpringBoneChain(scarf.bones, {
      stiffness: 0.5,
      drag: 0.22,
      gravityPower: 0.3,
      windInfluence: 0.14,
      tipOffset: new THREE.Vector3(0, -0.092, 0),
    });

    this.headCollider = { center: new THREE.Vector3(), radius: 0.13 };
    this.torsoCollider = { center: new THREE.Vector3(), radius: 0.17 };
    this.hair.colliders = [this.headCollider, this.torsoCollider];
    this.scarf.colliders = [this.torsoCollider];
    this.groundY = 0;
  }

  /** Pin / rest layout in the chest's local frame → world. */
  _restPoint(i, j, out) {
    const u = i / (this.cols - 1);
    const v = j / (this.rows - 1);
    const flare = 1 + 0.55 * v;
    out.set(
      THREE.MathUtils.lerp(0.19, -0.19, u) * flare,
      0.04 - v * 0.86,
      -0.15 - 0.035 * Math.sin(Math.PI * u) - 0.06 * v,
    );
    return out.applyMatrix4(this.rig.joints.chest.matrixWorld);
  }

  /** Re-seed all secondary motion from the current pose (after teleports). */
  reset() {
    this.rig.root.updateMatrixWorld(true);
    this.cloak.resetToPins((i, j, out) => this._restPoint(i, j, out));
    this.hair.reset();
    this.scarf.reset();
  }

  update(dt, groundY) {
    const J = this.rig.joints;
    this.rig.root.updateMatrixWorld(true);

    // Big jumps (teleports, vehicle exit snaps) → re-seed instead of exploding.
    J.chest.getWorldPosition(_p);
    if (_p.distanceToSquared(this._lastChest) > 1.5 * 1.5) this.reset();
    this._lastChest.copy(_p);

    for (let i = 0; i < this.cols; i++) this.cloak.setPinTarget(i, 0, this._restPoint(i, 0, _p));

    const c = this.capsules;
    J.pelvis.getWorldPosition(c.torso.a);
    J.chest.getWorldPosition(c.torso.b);
    _a.subVectors(c.torso.b, c.torso.a).normalize();
    c.torso.a.addScaledVector(_a, 0.02);
    c.torso.b.addScaledVector(_a, -0.04);
    // Shrink the torso collider when lying on the ground so it can't fight the floor.
    c.torso.r = THREE.MathUtils.clamp(Math.min(c.torso.a.y, c.torso.b.y) - groundY - 0.02, 0.08, 0.19);
    J.thighL.getWorldPosition(c.thighL.a);
    J.shinL.getWorldPosition(c.thighL.b);
    J.thighR.getWorldPosition(c.thighR.a);
    J.shinR.getWorldPosition(c.thighR.b);
    c.shinL.a.copy(c.thighL.b);
    J.footL.getWorldPosition(c.shinL.b);
    c.shinR.a.copy(c.thighR.b);
    J.footR.getWorldPosition(c.shinR.b);
    this.cloak.groundY = groundY;
    this.cloak.update(dt, this.windAt);

    J.head.getWorldPosition(this.headCollider.center);
    this.headCollider.center.y += 0.1;
    _b.copy(c.torso.a).lerp(c.torso.b, 0.6);
    this.torsoCollider.center.copy(_b);
    this.hair.update(dt, this.windAt);
    this.scarf.update(dt, this.windAt);
  }
}

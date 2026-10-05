import * as THREE from 'three';

const _worldPos = new THREE.Vector3();
const _parentQ = new THREE.Quaternion();
const _restQ = new THREE.Quaternion();
const _invQ = new THREE.Quaternion();
const _next = new THREE.Vector3();
const _inertia = new THREE.Vector3();
const _stiff = new THREE.Vector3();
const _ext = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _wind = new THREE.Vector3();
const _q = new THREE.Quaternion();

/**
 * Spring-bone chain (VRM-style) for hair, scarves, straps, tails.
 *
 * Each joint keeps a simulated "tail" point:
 *   next = tail + (tail - prevTail)·(1 - drag)              inertia
 *        + restDirection(parent)·stiffness·dt               return to rest
 *        + (gravity + wind·windInfluence)·dt                external
 * then is re-projected to the bone length, pushed out of sphere colliders,
 * and converted back into a local bone rotation. Cheap, stable, and plays
 * well with any animated parent (procedural rig or skinned GLTF).
 */
export class SpringBoneChain {
  /**
   * @param {THREE.Bone[]} bones root → tip; each bone's first child bone defines its axis,
   *   the last bone uses `tipOffset`.
   */
  constructor(
    bones,
    {
      stiffness = 1.2,
      drag = 0.35,
      gravityPower = 0.35,
      gravityDir = new THREE.Vector3(0, -1, 0),
      windInfluence = 0.06,
      hitRadius = 0.02,
      tipOffset = new THREE.Vector3(0, -0.08, 0),
      substep = 1 / 60,
    } = {},
  ) {
    this.bones = bones;
    this.stiffness = stiffness;
    this.drag = drag;
    this.gravityPower = gravityPower;
    this.gravityDir = gravityDir.clone().normalize();
    this.windInfluence = windInfluence;
    this.hitRadius = hitRadius;
    this.substep = substep;
    this._acc = 0;
    /** Sphere colliders in world space: {center: Vector3, radius: number} */
    this.colliders = [];

    this.joints = bones.map((bone, i) => {
      const child = bones[i + 1];
      const localTail = child ? child.position.clone() : tipOffset.clone();
      return {
        bone,
        restQ: bone.quaternion.clone(),
        axis: localTail.clone().normalize(),
        length: localTail.length(),
        tail: new THREE.Vector3(),
        prevTail: new THREE.Vector3(),
        localTail,
      };
    });
    this.reset();
  }

  /** Re-seed tails from the current pose (call after teleports / re-parenting). */
  reset() {
    for (const j of this.joints) {
      j.bone.updateWorldMatrix(true, false);
      j.tail.copy(j.localTail).applyMatrix4(j.bone.matrixWorld);
      j.prevTail.copy(j.tail);
    }
  }

  /**
   * @param {number} dt
   * @param {(p:THREE.Vector3, out:THREE.Vector3)=>THREE.Vector3} [windAt]
   */
  update(dt, windAt) {
    // Rigidly carry tails with the chain root for time we cannot simulate
    // (long frames), so hair doesn't trail metres behind after a hitch.
    const root = this.bones[0];
    root.updateWorldMatrix(true, false);
    _worldPos.setFromMatrixPosition(root.matrixWorld);
    const maxSteps = 4;
    this._acc += dt;
    let steps = Math.floor(this._acc / this.substep);
    if (steps > maxSteps && this._lastRoot) {
      _dir.subVectors(_worldPos, this._lastRoot).multiplyScalar(1 - maxSteps / steps);
      for (const j of this.joints) {
        j.tail.add(_dir);
        j.prevTail.add(_dir);
      }
      steps = maxSteps;
      this._acc = 0;
    } else {
      this._acc -= steps * this.substep;
    }
    (this._lastRoot ??= new THREE.Vector3()).copy(_worldPos);
    for (let i = 0; i < steps; i++) this._step(this.substep, windAt);
  }

  _step(dt, windAt) {
    for (const j of this.joints) {
      const bone = j.bone;
      bone.parent.updateWorldMatrix(true, false);
      bone.parent.getWorldQuaternion(_parentQ);
      // Rest orientation in world space.
      _restQ.copy(_parentQ).multiply(j.restQ);
      bone.quaternion.copy(j.restQ);
      bone.updateWorldMatrix(false, false);
      _worldPos.setFromMatrixPosition(bone.matrixWorld);

      _inertia.subVectors(j.tail, j.prevTail).multiplyScalar(1 - this.drag);
      _stiff
        .copy(j.axis)
        .applyQuaternion(_restQ)
        .multiplyScalar(this.stiffness * dt);
      _ext.copy(this.gravityDir).multiplyScalar(this.gravityPower * dt);
      if (windAt) _ext.addScaledVector(windAt(j.tail, _wind), this.windInfluence * dt);

      _next.copy(j.tail).add(_inertia).add(_stiff).add(_ext);
      // Keep bone length.
      _dir.subVectors(_next, _worldPos).normalize();
      _next.copy(_worldPos).addScaledVector(_dir, j.length);

      for (const c of this.colliders) {
        const r = c.radius + this.hitRadius;
        _dir.subVectors(_next, c.center);
        const d = _dir.length();
        if (d < r && d > 1e-6) {
          _next.copy(c.center).addScaledVector(_dir, r / d);
          _dir.subVectors(_next, _worldPos).normalize();
          _next.copy(_worldPos).addScaledVector(_dir, j.length);
        }
      }

      j.prevTail.copy(j.tail);
      j.tail.copy(_next);

      // Rotate the bone so its axis points at the new tail.
      _invQ.copy(_restQ).invert();
      _dir.subVectors(_next, _worldPos).applyQuaternion(_invQ).normalize();
      _q.setFromUnitVectors(j.axis, _dir);
      bone.quaternion.copy(j.restQ).multiply(_q);
      bone.updateWorldMatrix(false, true);
    }
  }
}

/**
 * Builds a tapered skinned tube driven by a spring chain (ponytail, scarf tail).
 * The tube hangs along -Y of `holder` (orient the holder to aim it).
 */
export function createSpringTail({
  holder,
  segments = 5,
  length = 0.45,
  radiusTop = 0.04,
  radiusBottom = 0.015,
  material,
  flatten = 1,
}) {
  const segLen = length / segments;
  const bones = [];
  let parent = holder;
  for (let i = 0; i < segments; i++) {
    const b = new THREE.Bone();
    b.position.set(0, i === 0 ? 0 : -segLen, 0);
    parent.add(b);
    bones.push(b);
    parent = b;
  }

  const geometry = new THREE.CylinderGeometry(radiusTop, radiusBottom, length, 8, segments * 3, false);
  geometry.translate(0, -length / 2, 0);
  geometry.scale(1, 1, flatten);
  const pos = geometry.attributes.position;
  const skinIndex = [];
  const skinWeight = [];
  for (let i = 0; i < pos.count; i++) {
    const d = THREE.MathUtils.clamp(-pos.getY(i) / segLen, 0, segments - 1e-4);
    const i0 = Math.floor(d);
    const f = d - i0;
    const i1 = Math.min(i0 + 1, segments - 1);
    skinIndex.push(i0, i1, 0, 0);
    skinWeight.push(1 - f, f, 0, 0);
  }
  geometry.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(skinIndex, 4));
  geometry.setAttribute('skinWeight', new THREE.Float32BufferAttribute(skinWeight, 4));

  const mesh = new THREE.SkinnedMesh(geometry, material);
  mesh.castShadow = true;
  mesh.frustumCulled = false;
  holder.add(mesh);
  holder.updateMatrixWorld(true);
  mesh.bind(new THREE.Skeleton(bones));
  return { mesh, bones };
}

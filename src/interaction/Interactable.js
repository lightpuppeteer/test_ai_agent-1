import * as THREE from 'three';

export const INTERACTION_TYPE = {
  SEAT: 'seat',
  TOWEL: 'towel',
  VEHICLE: 'vehicle',
};

const _m = new THREE.Matrix4();
const _s = new THREE.Vector3();

/**
 * An anchor is a local transform on an interactable that a character snaps
 * to (a seat, a towel, a car door…). Conventions (anchor local space):
 *  - SEAT:  origin on the seat surface where the pelvis rests, +Z = facing.
 *  - TOWEL: origin at the towel centre on the ground, +Y = surface normal,
 *           the head lies towards -Z.
 *  - DOOR:  origin on the ground outside the door, +Z facing the vehicle.
 */
export class Anchor {
  constructor({ id, position, quaternion = new THREE.Quaternion(), meta = {} }) {
    this.id = id;
    this.position = position.clone();
    this.quaternion = quaternion.clone();
    this.meta = meta;
    this.occupant = null;
  }

  get occupied() {
    return this.occupant !== null;
  }
}

/**
 * Something the player can interact with. Anchors are expressed relative to
 * `object` so they follow it when it moves (vehicles). Static props that are
 * merged into instanced batches get a lightweight, non-rendered Object3D.
 */
export class Interactable {
  /**
   * @param {object} o
   * @param {string} o.type INTERACTION_TYPE
   * @param {string} o.label UI prompt, e.g. "Sit"
   * @param {THREE.Object3D} o.object transform the anchors are relative to
   * @param {Anchor[]} o.anchors
   * @param {number} [o.radius] interaction range (bounding sphere, m)
   * @param {THREE.Vector3} [o.center] bounding-sphere centre in object space
   * @param {boolean} [o.dynamic] moves at runtime (re-indexed every frame)
   */
  constructor({
    id,
    type,
    label,
    object,
    anchors = [],
    radius = 1.6,
    center = new THREE.Vector3(),
    dynamic = false,
    data = {},
  }) {
    this.id = id ?? `${type}-${Interactable._nextId++}`;
    this.type = type;
    this.label = label;
    this.object = object;
    this.anchors = anchors;
    this.radius = radius;
    this.center = center;
    this.dynamic = dynamic;
    this.data = data;
    this.enabled = true;
  }

  /** Moving interactables must not use last frame's matrix (the renderer updates it later). */
  _syncMatrix() {
    if (this.dynamic) this.object.updateWorldMatrix(true, false);
  }

  /** World-space centre of the interaction volume. */
  getWorldCenter(out) {
    this._syncMatrix();
    return out.copy(this.center).applyMatrix4(this.object.matrixWorld);
  }

  /** World pose of an anchor. */
  getAnchorWorld(anchor, outPos, outQuat) {
    this._syncMatrix();
    _m.compose(anchor.position, anchor.quaternion, _s.set(1, 1, 1)).premultiply(this.object.matrixWorld);
    _m.decompose(outPos, outQuat, _s);
    return outPos;
  }

  /** Converts a local point (object space) to world. */
  localToWorld(local, out) {
    return out.copy(local).applyMatrix4(this.object.matrixWorld);
  }

  /** Nearest free anchor to a world position, optionally filtered by a predicate. */
  nearestFreeAnchor(worldPos, filter = null) {
    this._syncMatrix();
    let best = null;
    let bestD = Infinity;
    const p = _tmp;
    for (const a of this.anchors) {
      if (a.occupied || (filter && !filter(a))) continue;
      p.copy(a.position).applyMatrix4(this.object.matrixWorld);
      const d = p.distanceToSquared(worldPos);
      if (d < bestD) {
        bestD = d;
        best = a;
      }
    }
    return best;
  }

  get available() {
    return this.enabled && this.anchors.some((a) => !a.occupied);
  }
}
Interactable._nextId = 1;

const _tmp = new THREE.Vector3();

/** Creates an invisible transform root for interactables built into batches. */
export function staticRoot(position, yaw = 0) {
  const o = new THREE.Object3D();
  o.position.copy(position);
  o.rotation.y = yaw;
  o.updateMatrixWorld(true);
  return o;
}

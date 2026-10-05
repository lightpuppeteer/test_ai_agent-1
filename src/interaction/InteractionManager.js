import * as THREE from 'three';

const _c = new THREE.Vector3();
const _d = new THREE.Vector3();

/**
 * Proximity detection for interactables using bounding spheres.
 *
 *  - Static interactables (benches, towels) live in a uniform spatial hash,
 *    so a query only touches a handful of cells regardless of world size.
 *  - Dynamic ones (vehicles) are tested linearly every frame (few of them).
 *  - The "focus" is the best available candidate the player is inside of,
 *    scored by distance and by how much the player faces it. Focus changes
 *    are broadcast (HUD prompt).
 */
export class InteractionManager {
  constructor({ cellSize = 8 } = {}) {
    this.cellSize = cellSize;
    this.cells = new Map();
    this.dynamic = new Set();
    this.all = new Set();
    this.focus = null;
    this.listeners = new Set();
  }

  _key(ix, iz) {
    return `${ix},${iz}`;
  }

  register(interactable) {
    this.all.add(interactable);
    if (interactable.dynamic) {
      this.dynamic.add(interactable);
      return interactable;
    }
    interactable.object.updateMatrixWorld(true);
    interactable.getWorldCenter(_c);
    const r = interactable.radius;
    const s = this.cellSize;
    for (let ix = Math.floor((_c.x - r) / s); ix <= Math.floor((_c.x + r) / s); ix++)
      for (let iz = Math.floor((_c.z - r) / s); iz <= Math.floor((_c.z + r) / s); iz++) {
        const k = this._key(ix, iz);
        if (!this.cells.has(k)) this.cells.set(k, []);
        this.cells.get(k).push(interactable);
      }
    return interactable;
  }

  unregister(interactable) {
    this.all.delete(interactable);
    this.dynamic.delete(interactable);
    for (const list of this.cells.values()) {
      const i = list.indexOf(interactable);
      if (i >= 0) list.splice(i, 1);
    }
    if (this.focus === interactable) this._setFocus(null);
  }

  /** Interactables whose volume contains `position`. */
  query(position, out = []) {
    out.length = 0;
    const cell = this.cells.get(
      this._key(Math.floor(position.x / this.cellSize), Math.floor(position.z / this.cellSize)),
    );
    const test = (it) => {
      if (!it.enabled) return;
      it.getWorldCenter(_c);
      if (_c.distanceToSquared(position) <= it.radius * it.radius) out.push(it);
    };
    if (cell) for (const it of cell) test(it);
    for (const it of this.dynamic) test(it);
    return out;
  }

  /**
   * @param {THREE.Vector3} position character feet
   * @param {THREE.Vector3} forward character facing (unit, horizontal)
   */
  update(position, forward) {
    const probe = _probe.copy(position).setY(position.y + 0.5);
    const candidates = this.query(probe, _candidates);
    let best = null;
    let bestScore = Infinity;
    for (const it of candidates) {
      if (!it.available) continue;
      it.getWorldCenter(_c);
      _d.subVectors(_c, probe).setY(0);
      const dist = _d.length();
      const facing = dist > 1e-3 ? _d.multiplyScalar(1 / dist).dot(forward) : 1;
      const score = dist + (1 - facing) * 0.8;
      if (score < bestScore) {
        bestScore = score;
        best = it;
      }
    }
    this._setFocus(best);
  }

  clearFocus() {
    this._setFocus(null);
  }

  _setFocus(it) {
    if (it === this.focus) return;
    this.focus = it;
    for (const l of this.listeners) l(it);
  }

  onFocusChange(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
}

const _probe = new THREE.Vector3();
const _candidates = [];

import * as THREE from 'three';

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _n = new THREE.Vector3();
const _vel = new THREE.Vector3();
const _wind = new THREE.Vector3();
const _anchor = new THREE.Vector3(); // pin displacement per sub-step
const _seg = new THREE.Vector3();
const _p = new THREE.Vector3();

/**
 * Position-based Verlet cloth (cloaks, tunics, banners, flags).
 *
 *  - Grid of particles with structural, shear and bending distance
 *    constraints (Jakobsen-style relaxation, configurable iterations).
 *  - Pinned particles follow animated targets (e.g. the shoulders).
 *  - Aerodynamic wind per triangle: F = ½·ρ·Cd·A·(v_rel·n)·n, so cloth
 *    billows when facing the wind and slices through it edge-on — and the
 *    wearer's own motion creates relative wind for free.
 *  - Collision (a distance constraint inside the solver loop) with capsules
 *    (body parts, inflated per clothing layer via `collisionMargin` so outer
 *    layers stay outside inner ones), half-spaces (walls) and the ground.
 *  - Cloth-over-cloth layering (`innerLayers`): an outer garment (shirt
 *    hem) is kept radially outside an inner one (skirt) around the body
 *    axis, so separately simulated layers never interpenetrate.
 *  - Optional tube topology (`wrapU`) for skirts, hems and sleeves.
 *  - Fixed sub-stepping, independent of frame rate.
 */
export class VerletCloth {
  /**
   * @param {object} o
   * @param {number} o.cols particles across
   * @param {number} o.rows particles down
   * @param {(i:number,j:number,out:THREE.Vector3)=>void} o.initial initial world position per particle
   * @param {(i:number,j:number)=>boolean} o.isPinned
   * @param {THREE.Material} o.material
   */
  constructor({
    cols,
    rows,
    initial,
    isPinned,
    material,
    mass = 0.02, // kg per particle
    damping = 0.985,
    iterations = 6,
    bendStiffness = 0.35,
    drag = 0.6, // ½·ρ_air·C_d (flat plate ≈ 0.5·1.2·1.0)
    gravity = -9.81,
    substep = 1 / 90,
    wrapU = false, // connect the last column to the first (tubes)
    collisionMargin = 0.015, // extra clearance from colliders (clothing layer thickness)
  }) {
    this.wrapU = wrapU;
    this.collisionMargin = collisionMargin;
    this.cols = cols;
    this.rows = rows;
    this.count = cols * rows;
    this.mass = mass;
    this.damping = damping;
    this.iterations = iterations;
    this.drag = drag;
    this.gravity = gravity;
    this.substep = substep;
    this._acc = 0;

    this.pos = new Float32Array(this.count * 3);
    this.prev = new Float32Array(this.count * 3);
    this.force = new Float32Array(this.count * 3);
    this.invMass = new Float32Array(this.count);
    this.pinTargets = new Float32Array(this.count * 3);

    for (let j = 0; j < rows; j++)
      for (let i = 0; i < cols; i++) {
        const k = j * cols + i;
        initial(i, j, _p);
        this.pos.set([_p.x, _p.y, _p.z], k * 3);
        this.prev.set([_p.x, _p.y, _p.z], k * 3);
        this.pinTargets.set([_p.x, _p.y, _p.z], k * 3);
        this.invMass[k] = isPinned(i, j) ? 0 : 1 / mass;
      }

    // Constraints: [a, b, restLength, stiffness]
    const cons = [];
    const add = (i0, j0, i1, j1, stiffness) => {
      if (wrapU) i1 = (i1 + cols) % cols;
      if (i1 < 0 || j1 < 0 || i1 >= cols || j1 >= rows || (i1 === i0 && j1 === j0)) return;
      const a = j0 * cols + i0;
      const b = j1 * cols + i1;
      const rest = Math.hypot(
        this.pos[a * 3] - this.pos[b * 3],
        this.pos[a * 3 + 1] - this.pos[b * 3 + 1],
        this.pos[a * 3 + 2] - this.pos[b * 3 + 2],
      );
      cons.push(a, b, rest, stiffness);
    };
    for (let j = 0; j < rows; j++)
      for (let i = 0; i < cols; i++) {
        add(i, j, i + 1, j, 1); // structural
        add(i, j, i, j + 1, 1);
        add(i, j, i + 1, j + 1, 0.8); // shear
        add(i + 1, j, i, j + 1, 0.8);
        add(i, j, i + 2, j, bendStiffness); // bending
        add(i, j, i, j + 2, bendStiffness);
      }
    this.constraints = new Float32Array(cons);

    // Render mesh (double-sided, normals recomputed each frame).
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute(
      'position',
      new THREE.BufferAttribute(new Float32Array(this.pos), 3).setUsage(THREE.DynamicDrawUsage),
    );
    const uv = new Float32Array(this.count * 2);
    const index = [];
    for (let j = 0; j < rows; j++)
      for (let i = 0; i < cols; i++) {
        uv.set([i / (cols - 1), 1 - j / (rows - 1)], (j * cols + i) * 2);
        if ((i < cols - 1 || wrapU) && j < rows - 1) {
          const a = j * cols + i;
          const b = j * cols + ((i + 1) % cols);
          index.push(a, a + cols, b, b, a + cols, b + cols);
        }
      }
    geometry.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    geometry.setIndex(index);
    geometry.computeVertexNormals();
    this.triangles = index;
    this.mesh = new THREE.Mesh(geometry, material);
    this.mesh.frustumCulled = false;
    this.mesh.castShadow = true;
    this.mesh.receiveShadow = true;
    this.mesh.name = 'VerletCloth';

    /** Capsule colliders: {a: Vector3, b: Vector3, r: number} in world space. */
    this.capsules = [];
    // Collider motion is interpolated across sub-steps like the pins: a limb
    // that moved 15 cm during a long frame must sweep through the sub-steps,
    // not teleport in the first one (which would fling the cloth away).
    this._capFrom = []; // capsule endpoints at the end of the previous update
    this._capWork = []; // interpolated capsules used by the solver
    this._capReset = true;
    /** Length of the last integration sub-step (time-corrected Verlet). */
    this.lastSubstep = substep;
    /**
     * Inner cloth layers this cloth must stay outside of:
     * { cloth: VerletCloth, center: Vector3 (body axis, world), gap: number,
     *   maxRow: number (only the inner cloth's rows ≤ maxRow), band, width }
     */
    this.innerLayers = [];
    /** Half-space colliders: {normal: Vector3 (unit), constant: number} — keeps n·p + c ≥ margin. */
    this.planes = [];
    this.groundY = -Infinity;
    /** When false the simulation is frozen (distance LOD); pins still update the mesh. */
    this.active = true;
  }

  setPinTarget(i, j, p) {
    this.pinTargets.set([p.x, p.y, p.z], (j * this.cols + i) * 3);
  }

  /** Snaps everything to the pins (after teleports). */
  resetToPins(offsetFn) {
    for (let k = 0; k < this.count; k++) {
      const i = k % this.cols;
      const j = Math.floor(k / this.cols);
      offsetFn(i, j, _p);
      this.pos.set([_p.x, _p.y, _p.z], k * 3);
      this.prev.set([_p.x, _p.y, _p.z], k * 3);
    }
    this._capReset = true;
  }

  /**
   * @param {number} dt frame delta
   * @param {(p:THREE.Vector3, out:THREE.Vector3)=>THREE.Vector3} windAt wind velocity sampler (m/s)
   */
  update(dt, windAt) {
    if (!this.active) {
      this._capReset = true; // colliders moved on without us
      return;
    }
    this._acc += dt;
    let h = this.substep;
    let steps = Math.floor(this._acc / h);
    if (steps === 0) return;
    // Long frame (hitch, slow device): stretch the sub-step (up to 1/40 s)
    // so the frame is still simulated in real time — gravity, drag and limb
    // speeds stay physical. Only beyond maxSteps·hMax (a real hitch) is the
    // remainder carried rigidly with the pins.
    const maxSteps = 10;
    const hMax = 1 / 40;
    let carried = 0;
    if (steps > maxSteps) {
      h = Math.min(hMax, this._acc / maxSteps);
      steps = maxSteps;
      carried = Math.max(0, 1 - (h * steps) / this._acc);
      if (carried > 0) this._carryRigid(carried);
      this._acc = 0;
    } else {
      this._acc -= steps * h;
    }
    this._beginColliderSweep(carried);
    if (carried > 0) {
      // The carried colliders may now overlap the rigidly carried cloth:
      // resolve that overlap kinematically (no velocity injection).
      this._sweepColliders(0);
      this._collide(true);
    }
    // Interpolate pin targets across sub-steps for smooth fast motion.
    const startPins = this._pinStart ?? (this._pinStart = new Float32Array(this.pinTargets.length));
    for (let k = 0; k < this.count; k++) {
      if (this.invMass[k] === 0) startPins.set(this.pos.subarray(k * 3, k * 3 + 3), k * 3);
    }
    // Anchor motion per sub-step (average pin displacement): damping acts on
    // velocity *relative* to it, so a walking wearer doesn't drag the cloth
    // through a fake headwind (real air resistance is the aerodynamic term).
    let pins = 0;
    _anchor.set(0, 0, 0);
    for (let k = 0; k < this.count; k++) {
      if (this.invMass[k] !== 0) continue;
      _anchor.x += this.pinTargets[k * 3] - startPins[k * 3];
      _anchor.y += this.pinTargets[k * 3 + 1] - startPins[k * 3 + 1];
      _anchor.z += this.pinTargets[k * 3 + 2] - startPins[k * 3 + 2];
      pins++;
    }
    if (pins) _anchor.multiplyScalar(1 / (pins * steps));
    for (let s = 1; s <= steps; s++) {
      const a = s / steps;
      for (let k = 0; k < this.count; k++) {
        if (this.invMass[k] !== 0) continue;
        for (let c = 0; c < 3; c++)
          this.pos[k * 3 + c] = startPins[k * 3 + c] + (this.pinTargets[k * 3 + c] - startPins[k * 3 + c]) * a;
      }
      this._sweepColliders(a);
      this._step(h, windAt);
    }
    this._endColliderSweep();
    this._writeMesh();
  }

  /** Prepares sub-step interpolation of the capsules (`carried`: fraction already applied rigidly). */
  _beginColliderSweep(carried) {
    const caps = this.capsules;
    const from = this._capFrom;
    const work = this._capWork;
    const reset = this._capReset || from.length !== caps.length;
    for (let i = 0; i < caps.length; i++) {
      from[i] ??= { a: new THREE.Vector3(), b: new THREE.Vector3() };
      work[i] ??= { name: '', a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0 };
      const f = from[i];
      const c = caps[i];
      // Teleports (or the first frame) start from the current pose.
      if (reset || f.a.distanceToSquared(c.a) > 1) {
        f.a.copy(c.a);
        f.b.copy(c.b);
      } else if (carried > 0) {
        f.a.lerp(c.a, carried);
        f.b.lerp(c.b, carried);
      }
      work[i].name = c.name;
      work[i].r = c.r;
    }
    from.length = work.length = caps.length;
    this._capReset = false;
  }

  _sweepColliders(alpha) {
    const caps = this.capsules;
    for (let i = 0; i < caps.length; i++) {
      this._capWork[i].a.lerpVectors(this._capFrom[i].a, caps[i].a, alpha);
      this._capWork[i].b.lerpVectors(this._capFrom[i].b, caps[i].b, alpha);
    }
  }

  _endColliderSweep() {
    for (let i = 0; i < this.capsules.length; i++) {
      this._capFrom[i].a.copy(this.capsules[i].a);
      this._capFrom[i].b.copy(this.capsules[i].b);
    }
  }

  /**
   * Long-frame catch-up: advances everything by `fraction` of this frame's
   * motion without simulating it. Free particles move rigidly with the
   * average pin motion; each pin moves by the same fraction of its *own*
   * motion, so the part that is simulated afterwards (pins and swept
   * colliders alike) happens at real-time speed — e.g. a waist ring skinned
   * to the thighs doesn't replay a whole stride in a few sub-steps.
   */
  _carryRigid(fraction) {
    let n = 0;
    _p.set(0, 0, 0);
    for (let k = 0; k < this.count; k++) {
      if (this.invMass[k] !== 0) continue;
      _p.x += this.pinTargets[k * 3] - this.pos[k * 3];
      _p.y += this.pinTargets[k * 3 + 1] - this.pos[k * 3 + 1];
      _p.z += this.pinTargets[k * 3 + 2] - this.pos[k * 3 + 2];
      n++;
    }
    if (n === 0) return;
    _p.multiplyScalar(fraction / n);
    for (let k = 0; k < this.count; k++) {
      const pinned = this.invMass[k] === 0;
      for (let c = 0; c < 3; c++) {
        const i = k * 3 + c;
        const d = pinned ? (this.pinTargets[i] - this.pos[i]) * fraction : c === 0 ? _p.x : c === 1 ? _p.y : _p.z;
        this.pos[i] += d;
        this.prev[i] += d;
      }
    }
  }

  _step(h, windAt) {
    const { pos, prev, force, invMass } = this;
    // Time-corrected Verlet: (pos - prev) spans the *previous* sub-step,
    // which differs from h when long frames stretch the step.
    const hp = this.lastSubstep;
    const ratio = h / hp;
    force.fill(0);

    // Aerodynamic forces per triangle.
    const tri = this.triangles;
    for (let t = 0; t < tri.length; t += 3) {
      const ia = tri[t] * 3;
      const ib = tri[t + 1] * 3;
      const ic = tri[t + 2] * 3;
      _a.fromArray(pos, ia);
      _b.fromArray(pos, ib);
      _c.fromArray(pos, ic);
      _n.subVectors(_b, _a).cross(_seg.subVectors(_c, _a));
      const area2 = _n.length();
      if (area2 < 1e-8) continue;
      _n.multiplyScalar(1 / area2);
      // Triangle velocity (average of particle velocities).
      _vel.set(
        (pos[ia] - prev[ia] + pos[ib] - prev[ib] + pos[ic] - prev[ic]) / (3 * hp),
        (pos[ia + 1] - prev[ia + 1] + pos[ib + 1] - prev[ib + 1] + pos[ic + 1] - prev[ic + 1]) / (3 * hp),
        (pos[ia + 2] - prev[ia + 2] + pos[ib + 2] - prev[ib + 2] + pos[ic + 2] - prev[ic + 2]) / (3 * hp),
      );
      _p.addVectors(_a, _b)
        .add(_c)
        .multiplyScalar(1 / 3);
      windAt(_p, _wind);
      _wind.sub(_vel); // relative air velocity
      const vn = _wind.dot(_n);
      const f = (this.drag * (area2 * 0.5) * vn * Math.abs(vn)) / 3;
      for (const i of [ia, ib, ic]) {
        force[i] += _n.x * f;
        force[i + 1] += _n.y * f;
        force[i + 2] += _n.z * f;
      }
    }

    // Verlet integration.
    const h2 = h * h;
    const d = h === this.substep ? this.damping : Math.pow(this.damping, h / this.substep);
    for (let k = 0; k < this.count; k++) {
      if (invMass[k] === 0) continue;
      const i = k * 3;
      for (let c = 0; c < 3; c++) {
        const x = pos[i + c];
        const acc = force[i + c] * invMass[k] + (c === 1 ? this.gravity : 0);
        const anchor = c === 0 ? _anchor.x : c === 1 ? _anchor.y : _anchor.z;
        pos[i + c] = x + anchor + ((x - prev[i + c]) * ratio - anchor) * d + acc * h2;
        prev[i + c] = x;
      }
    }
    this.lastSubstep = h;

    // Constraint relaxation + collisions.
    const cons = this.constraints;
    for (let it = 0; it < this.iterations; it++) {
      for (let c = 0; c < cons.length; c += 4) {
        const a = cons[c] * 3;
        const b = cons[c + 1] * 3;
        const rest = cons[c + 2];
        const stiff = cons[c + 3];
        const wa = invMass[cons[c]];
        const wb = invMass[cons[c + 1]];
        const w = wa + wb;
        if (w === 0) continue;
        const dx = pos[b] - pos[a];
        const dy = pos[b + 1] - pos[a + 1];
        const dz = pos[b + 2] - pos[a + 2];
        const len = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1e-6;
        // Only resist stretching for bending links (cloth folds freely).
        let diff = (len - rest) / len;
        if (stiff < 0.5 && diff < 0) diff *= 0.2;
        const s = (diff * stiff) / w;
        pos[a] += dx * s * wa;
        pos[a + 1] += dy * s * wa;
        pos[a + 2] += dz * s * wa;
        pos[b] -= dx * s * wb;
        pos[b + 1] -= dy * s * wb;
        pos[b + 2] -= dz * s * wb;
      }
      this._collide();
    }
    for (const layer of this.innerLayers) this._stayOutside(layer);
  }

  /**
   * Layering constraint: each particle is pushed out horizontally, away from
   * the body axis, until it lies `gap` outside the inner cloth's surface
   * along its own radial ray. That surface radius is the largest radial
   * projection among inner particles inside a narrow window around the ray
   * (±`band` in height, ±`width` sideways), so folds are respected and the
   * result is a fixed point. Runs once per sub-step after the solver
   * iterations; it only ever moves particles outward, so it stays stable.
   */
  _stayOutside({ cloth, center, gap = 0.006, maxRow = cloth.rows - 1, band = 0.045, width = 0.035 }) {
    const { pos, invMass } = this;
    const Q = cloth.pos;
    const n = Math.min(cloth.count, (maxRow + 1) * cloth.cols);
    for (let k = 0; k < this.count; k++) {
      if (invMass[k] === 0) continue;
      const i = k * 3;
      const ox = pos[i] - center.x;
      const oz = pos[i + 2] - center.z;
      const rp = Math.hypot(ox, oz);
      if (rp < 1e-5) continue;
      const ux = ox / rp;
      const uz = oz / rp;
      const py = pos[i + 1];
      let surface = -1;
      for (let q = 0; q < n; q++) {
        if (Math.abs(Q[q * 3 + 1] - py) > band) continue;
        const qx = Q[q * 3] - center.x;
        const qz = Q[q * 3 + 2] - center.z;
        const along = qx * ux + qz * uz;
        if (along > surface && Math.abs(qz * ux - qx * uz) < width) surface = along;
      }
      if (surface < 0) continue;
      const need = surface + gap;
      if (rp < need) {
        pos[i] = center.x + ux * need;
        pos[i + 2] = center.z + uz * need;
      }
    }
  }

  /** @param {boolean} [kinematic] move `prev` with the correction (no velocity change) */
  _collide(kinematic = false) {
    const { pos, prev, invMass } = this;
    for (let k = 0; k < this.count; k++) {
      if (invMass[k] === 0) continue;
      const i = k * 3;
      _p.set(pos[i], pos[i + 1], pos[i + 2]);
      for (const cap of this._capWork) {
        // Closest point on segment a-b.
        _seg.subVectors(cap.b, cap.a);
        const t = THREE.MathUtils.clamp(_a.subVectors(_p, cap.a).dot(_seg) / Math.max(_seg.lengthSq(), 1e-8), 0, 1);
        _b.copy(cap.a).addScaledVector(_seg, t);
        _c.subVectors(_p, _b);
        const dist = _c.length();
        const r = cap.r + this.collisionMargin;
        if (dist < r) {
          if (dist < 1e-5) _c.set(0, 0, -1);
          else _c.multiplyScalar(1 / dist);
          _p.copy(_b).addScaledVector(_c, r);
        }
      }
      for (const pl of this.planes) {
        const d = pl.normal.dot(_p) + pl.constant - this.collisionMargin;
        if (d < 0) _p.addScaledVector(pl.normal, -d);
      }
      if (_p.y < this.groundY + this.collisionMargin) _p.y = this.groundY + this.collisionMargin;
      if (kinematic) {
        prev[i] += _p.x - pos[i];
        prev[i + 1] += _p.y - pos[i + 1];
        prev[i + 2] += _p.z - pos[i + 2];
      }
      pos[i] = _p.x;
      pos[i + 1] = _p.y;
      pos[i + 2] = _p.z;
    }
  }

  _writeMesh() {
    const attr = this.mesh.geometry.attributes.position;
    attr.array.set(this.pos);
    attr.needsUpdate = true;
    this.mesh.geometry.computeVertexNormals();
  }
}

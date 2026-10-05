import * as THREE from 'three';

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _n = new THREE.Vector3();
const _vel = new THREE.Vector3();
const _wind = new THREE.Vector3();
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
 *  - Collision with capsules (body parts) and a ground plane.
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
  }) {
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
      if (i1 < 0 || j1 < 0 || i1 >= cols || j1 >= rows) return;
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
        if (i < cols - 1 && j < rows - 1) {
          const a = j * cols + i;
          index.push(a, a + cols, a + 1, a + 1, a + cols, a + cols + 1);
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
    this.groundY = -Infinity;
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
  }

  /**
   * @param {number} dt frame delta
   * @param {(p:THREE.Vector3, out:THREE.Vector3)=>THREE.Vector3} windAt wind velocity sampler (m/s)
   */
  update(dt, windAt) {
    this._acc += dt;
    let steps = Math.floor(this._acc / this.substep);
    if (steps === 0) return;
    // Long frame (hitch, background tab, slow device): simulate at most
    // `maxSteps` and move the cloth rigidly with its pins for the rest, so it
    // follows the body instead of lagging behind and over-stretching.
    const maxSteps = 8;
    if (steps > maxSteps) {
      this._carryRigid(1 - maxSteps / steps);
      steps = maxSteps;
      this._acc = 0;
    } else {
      this._acc -= steps * this.substep;
    }
    // Interpolate pin targets across sub-steps for smooth fast motion.
    const startPins = this._pinStart ?? (this._pinStart = new Float32Array(this.pinTargets.length));
    for (let k = 0; k < this.count; k++) {
      if (this.invMass[k] === 0) startPins.set(this.pos.subarray(k * 3, k * 3 + 3), k * 3);
    }
    for (let s = 1; s <= steps; s++) {
      const a = s / steps;
      for (let k = 0; k < this.count; k++) {
        if (this.invMass[k] !== 0) continue;
        for (let c = 0; c < 3; c++)
          this.pos[k * 3 + c] = startPins[k * 3 + c] + (this.pinTargets[k * 3 + c] - startPins[k * 3 + c]) * a;
      }
      this._step(this.substep, windAt);
    }
    this._writeMesh();
  }

  /** Translates every particle by `fraction` of the average pin motion. */
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
      for (let c = 0; c < 3; c++) {
        const d = c === 0 ? _p.x : c === 1 ? _p.y : _p.z;
        this.pos[k * 3 + c] += d;
        this.prev[k * 3 + c] += d;
      }
    }
  }

  _step(h, windAt) {
    const { pos, prev, force, invMass } = this;
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
        (pos[ia] - prev[ia] + pos[ib] - prev[ib] + pos[ic] - prev[ic]) / (3 * h),
        (pos[ia + 1] - prev[ia + 1] + pos[ib + 1] - prev[ib + 1] + pos[ic + 1] - prev[ic + 1]) / (3 * h),
        (pos[ia + 2] - prev[ia + 2] + pos[ib + 2] - prev[ib + 2] + pos[ic + 2] - prev[ic + 2]) / (3 * h),
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
    const d = this.damping;
    for (let k = 0; k < this.count; k++) {
      if (invMass[k] === 0) continue;
      const i = k * 3;
      for (let c = 0; c < 3; c++) {
        const x = pos[i + c];
        const acc = force[i + c] * invMass[k] + (c === 1 ? this.gravity : 0);
        pos[i + c] = x + (x - prev[i + c]) * d + acc * h2;
        prev[i + c] = x;
      }
    }

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
  }

  _collide() {
    const { pos, invMass } = this;
    for (let k = 0; k < this.count; k++) {
      if (invMass[k] === 0) continue;
      const i = k * 3;
      _p.set(pos[i], pos[i + 1], pos[i + 2]);
      for (const cap of this.capsules) {
        // Closest point on segment a-b.
        _seg.subVectors(cap.b, cap.a);
        const t = THREE.MathUtils.clamp(_a.subVectors(_p, cap.a).dot(_seg) / Math.max(_seg.lengthSq(), 1e-8), 0, 1);
        _b.copy(cap.a).addScaledVector(_seg, t);
        _c.subVectors(_p, _b);
        const dist = _c.length();
        const r = cap.r + 0.015;
        if (dist < r) {
          if (dist < 1e-5) _c.set(0, 0, -1);
          else _c.multiplyScalar(1 / dist);
          _p.copy(_b).addScaledVector(_c, r);
        }
      }
      if (_p.y < this.groundY + 0.015) _p.y = this.groundY + 0.015;
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

import * as THREE from 'three';
import { PHYSICS, GROUPS, SURFACE } from '../config.js';

const _v = new THREE.Vector3();

/**
 * Thin, opinionated wrapper around a Rapier world.
 *
 *  - Fixed timestep stepping (driven by Engine).
 *  - Render interpolation: `link(object3D, body)` keeps a mesh in sync with a
 *    rigid body, interpolating between the last two physics states so motion
 *    is smooth at any display refresh rate.
 *  - Scopes: everything created while a scope is active is tracked so a
 *    chapter can be unloaded without leaking bodies.
 *  - Collider metadata (surface type, owner) keyed by collider handle.
 *  - Grouped static colliders: one fixed body carrying many colliders, which
 *    is far cheaper than one body per wall/arch/bench.
 */
export class PhysicsWorld {
  /** Loads Rapier lazily (separate chunk: the WASM is inlined as base64). */
  static async create() {
    const RAPIER = (await import('@dimforge/rapier3d-compat')).default;
    await RAPIER.init();
    return new PhysicsWorld(RAPIER);
  }

  constructor(RAPIER) {
    this.RAPIER = RAPIER;
    this.world = new RAPIER.World({ x: 0, y: PHYSICS.gravity, z: 0 });
    this.world.timestep = PHYSICS.fixedTimeStep;

    this._links = [];
    this._linkByBody = new Map();
    this._scopes = [];
    this._colliderInfo = new Map();

    this._debugLines = null;
  }

  // ---------------------------------------------------------------------------
  // Stepping & interpolation
  // ---------------------------------------------------------------------------
  step() {
    this.world.step();
  }

  /** Records the post-step pose of every linked body (called by Engine). */
  capture() {
    for (const l of this._links) {
      l.prevPos.copy(l.currPos);
      l.prevQuat.copy(l.currQuat);
      const t = l.body.translation();
      const r = l.body.rotation();
      l.currPos.set(t.x, t.y, t.z);
      l.currQuat.set(r.x, r.y, r.z, r.w);
    }
  }

  /** Writes interpolated poses to linked objects (called once per frame). */
  interpolate(alpha) {
    for (const l of this._links) {
      if (!l.enabled) continue;
      if (l.interpolate) {
        l.object.position.lerpVectors(l.prevPos, l.currPos, alpha);
        l.object.quaternion.slerpQuaternions(l.prevQuat, l.currQuat, alpha);
      } else {
        l.object.position.copy(l.currPos);
        l.object.quaternion.copy(l.currQuat);
      }
      if (l.offset) l.object.position.add(_v.copy(l.offset).applyQuaternion(l.object.quaternion));
    }
  }

  /**
   * Keeps `object` (must live in world space) glued to `body`.
   * @param {THREE.Object3D} object
   * @param {RAPIER.RigidBody} body
   * @param {{interpolate?: boolean, offset?: THREE.Vector3}} [opts]
   */
  link(object, body, { interpolate = true, offset = null } = {}) {
    const t = body.translation();
    const r = body.rotation();
    const link = {
      object,
      body,
      interpolate,
      offset,
      enabled: true,
      prevPos: new THREE.Vector3(t.x, t.y, t.z),
      currPos: new THREE.Vector3(t.x, t.y, t.z),
      prevQuat: new THREE.Quaternion(r.x, r.y, r.z, r.w),
      currQuat: new THREE.Quaternion(r.x, r.y, r.z, r.w),
    };
    this._links.push(link);
    this._linkByBody.set(body.handle, link);
    return link;
  }

  unlink(body) {
    const link = this._linkByBody.get(body.handle);
    if (!link) return;
    this._linkByBody.delete(body.handle);
    this._links.splice(this._links.indexOf(link), 1);
  }

  /** Call after teleporting a body so interpolation does not smear across the jump. */
  resetInterpolation(body) {
    const link = this._linkByBody.get(body.handle);
    if (!link) return;
    const t = body.translation();
    const r = body.rotation();
    link.prevPos.set(t.x, t.y, t.z);
    link.currPos.copy(link.prevPos);
    link.prevQuat.set(r.x, r.y, r.z, r.w);
    link.currQuat.copy(link.prevQuat);
  }

  /** Returns the interpolated (render) pose of a linked body. */
  getRenderPose(body, outPos, outQuat) {
    const link = this._linkByBody.get(body.handle);
    if (!link) return false;
    if (outPos) outPos.copy(link.object.position);
    if (outQuat) outQuat.copy(link.object.quaternion);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Creation with scope tracking
  // ---------------------------------------------------------------------------
  pushScope() {
    const scope = { bodies: [], colliders: [], controllers: [], links: [] };
    this._scopes.push(scope);
    return scope;
  }

  popScope() {
    return this._scopes.pop();
  }

  get _scope() {
    return this._scopes[this._scopes.length - 1] ?? null;
  }

  createRigidBody(desc) {
    const body = this.world.createRigidBody(desc);
    this._scope?.bodies.push(body);
    return body;
  }

  /**
   * @param {RAPIER.ColliderDesc} desc
   * @param {RAPIER.RigidBody} [body]
   * @param {{surface?: object, owner?: any}} [info]
   */
  createCollider(desc, body, info) {
    const collider = this.world.createCollider(desc, body);
    if (!body) this._scope?.colliders.push(collider);
    if (info) this._colliderInfo.set(collider.handle, info);
    return collider;
  }

  setColliderInfo(collider, info) {
    this._colliderInfo.set(collider.handle, info);
  }

  getColliderInfo(collider) {
    return collider ? this._colliderInfo.get(collider.handle) : undefined;
  }

  removeRigidBody(body) {
    this.unlink(body);
    for (let i = 0; i < body.numColliders(); i++) this._colliderInfo.delete(body.collider(i).handle);
    this.world.removeRigidBody(body);
  }

  trackController(controller, kind) {
    this._scope?.controllers.push({ controller, kind });
  }

  /** Removes everything created inside `scope` (chapter unload). */
  disposeScope(scope) {
    for (const { controller, kind } of scope.controllers) {
      if (kind === 'vehicle') this.world.removeVehicleController(controller);
      else if (kind === 'character') this.world.removeCharacterController(controller);
    }
    for (const c of scope.colliders) {
      this._colliderInfo.delete(c.handle);
      this.world.removeCollider(c, false);
    }
    for (const b of scope.bodies) this.removeRigidBody(b);
    scope.bodies.length = scope.colliders.length = scope.controllers.length = 0;
  }

  /**
   * Creates a fixed body that groups many static colliders (city blocks,
   * plazas, sea wall…). Colliders are positioned relative to the body.
   */
  createStaticGroup(name, { position = null, surface = SURFACE.STONE } = {}) {
    const desc = this.RAPIER.RigidBodyDesc.fixed();
    if (position) desc.setTranslation(position.x, position.y, position.z);
    const body = this.createRigidBody(desc);
    return new StaticColliderGroup(this, body, name, surface);
  }

  // ---------------------------------------------------------------------------
  // Scene queries
  // ---------------------------------------------------------------------------
  /**
   * Ray cast returning a plain object or null.
   * @returns {{point: THREE.Vector3, normal: THREE.Vector3, distance: number, collider: RAPIER.Collider} | null}
   */
  raycast(origin, direction, maxDistance, groups = GROUPS.QUERY_CAMERA, excludeBody = undefined) {
    const ray = new this.RAPIER.Ray(origin, direction);
    const hit = this.world.castRayAndGetNormal(ray, maxDistance, true, undefined, groups, undefined, excludeBody);
    if (!hit) return null;
    const d = hit.timeOfImpact;
    return {
      distance: d,
      point: new THREE.Vector3(origin.x + direction.x * d, origin.y + direction.y * d, origin.z + direction.z * d),
      normal: new THREE.Vector3(hit.normal.x, hit.normal.y, hit.normal.z),
      collider: hit.collider,
    };
  }

  /** True when a capsule placed at `position` (centre) overlaps nothing. */
  isCapsuleFree(position, halfHeight, radius, groups = GROUPS.QUERY_SPAWN, excludeBody = undefined) {
    const shape = new this.RAPIER.Capsule(halfHeight, radius);
    const hit = this.world.intersectionWithShape(
      position,
      { x: 0, y: 0, z: 0, w: 1 },
      shape,
      undefined,
      groups,
      undefined,
      excludeBody,
    );
    return !hit;
  }

  // ---------------------------------------------------------------------------
  // Debug rendering
  // ---------------------------------------------------------------------------
  setDebugVisible(scene, visible) {
    if (visible && !this._debugLines) {
      const geom = new THREE.BufferGeometry();
      const mat = new THREE.LineBasicMaterial({
        vertexColors: true,
        depthTest: false,
        transparent: true,
        opacity: 0.75,
        fog: false,
      });
      this._debugLines = new THREE.LineSegments(geom, mat);
      this._debugLines.frustumCulled = false;
      this._debugLines.renderOrder = 999;
      scene.add(this._debugLines);
    } else if (!visible && this._debugLines) {
      scene.remove(this._debugLines);
      this._debugLines.geometry.dispose();
      this._debugLines.material.dispose();
      this._debugLines = null;
    }
  }

  get debugVisible() {
    return !!this._debugLines;
  }

  updateDebug() {
    if (!this._debugLines) return;
    const { vertices, colors } = this.world.debugRender();
    const g = this._debugLines.geometry;
    g.setAttribute('position', new THREE.BufferAttribute(vertices, 3));
    g.setAttribute('color', new THREE.BufferAttribute(colors, 4));
  }
}

/**
 * A fixed rigid body carrying many colliders, with helpers that accept
 * Three.js math types so level-building code stays readable.
 */
export class StaticColliderGroup {
  constructor(physics, body, name, surface) {
    this.physics = physics;
    this.body = body;
    this.name = name;
    this.surface = surface;
    this.colliders = [];
  }

  _finish(desc, { position, quaternion, surface, friction, groups = GROUPS.STATIC, owner } = {}) {
    if (position) desc.setTranslation(position.x, position.y, position.z);
    if (quaternion) desc.setRotation({ x: quaternion.x, y: quaternion.y, z: quaternion.z, w: quaternion.w });
    const s = surface ?? this.surface;
    desc.setFriction(friction ?? s.friction);
    desc.setCollisionGroups(groups);
    const c = this.physics.createCollider(desc, this.body, { surface: s, owner: owner ?? this.name });
    this.colliders.push(c);
    return c;
  }

  /** Axis-aligned or rotated box. `size` is full extents. */
  addBox(position, size, quaternion = null, opts = {}) {
    const d = this.physics.RAPIER.ColliderDesc.cuboid(size.x / 2, size.y / 2, size.z / 2);
    return this._finish(d, { ...opts, position, quaternion });
  }

  /** Box from a Three.js mesh's world transform and its geometry bounding box. */
  addBoxFromMesh(mesh, opts = {}) {
    mesh.updateWorldMatrix(true, false);
    const g = mesh.geometry;
    if (!g.boundingBox) g.computeBoundingBox();
    const size = g.boundingBox.getSize(new THREE.Vector3());
    const centre = g.boundingBox.getCenter(new THREE.Vector3());
    const pos = new THREE.Vector3();
    const quat = new THREE.Quaternion();
    const scl = new THREE.Vector3();
    mesh.matrixWorld.decompose(pos, quat, scl);
    size.multiply(scl);
    centre.multiply(scl).applyQuaternion(quat).add(pos);
    return this.addBox(centre, size, quat, opts);
  }

  addCylinder(position, halfHeight, radius, quaternion = null, opts = {}) {
    const d = this.physics.RAPIER.ColliderDesc.cylinder(halfHeight, radius);
    return this._finish(d, { ...opts, position, quaternion });
  }

  /** Exact triangle collider for odd shapes (use sparingly). */
  addTrimesh(geometry, matrix = null, opts = {}) {
    const g = geometry.index ? geometry : geometry.toNonIndexed();
    const pos = g.attributes.position;
    const verts = new Float32Array(pos.count * 3);
    for (let i = 0; i < pos.count; i++) {
      _v.fromBufferAttribute(pos, i);
      if (matrix) _v.applyMatrix4(matrix);
      verts.set([_v.x, _v.y, _v.z], i * 3);
    }
    const indices = g.index ? new Uint32Array(g.index.array) : Uint32Array.from({ length: pos.count }, (_, i) => i);
    const d = this.physics.RAPIER.ColliderDesc.trimesh(verts, indices);
    return this._finish(d, opts);
  }
}

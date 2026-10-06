import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

/**
 * Authored character (Blender → glTF) adapter.
 *
 * The art pipeline (art/blender/scripts) exports a skinned glTF whose
 * skeleton uses the game's joint names (pelvis, spine, chest, neck, head,
 * upperArmL…footR) plus optional extra bones (e.g. hair0…hair3 for a spring
 * ponytail). Its bind pose is the game's rest pose: standing, arms relaxed at
 * the sides, +Z forward, +X to the character's left, feet on y = 0.
 *
 * Only the *joint positions* of the glTF skeleton are used: CharacterMesh
 * rebuilds its own skeleton with identity rest rotations at those positions
 * (the convention every procedural pose in CharacterRig is written against)
 * and rebinds the authored meshes to it. Blender's bone rolls and lengths
 * therefore never matter.
 *
 * Mesh parts are looked up by node name ("Body", "Hair", "Tunic", …). The body
 * carries a `_COVER` vertex attribute: per outfit channel, 1 where clothing
 * fully covers the skin, so the body shader can drop hidden skin instead of
 * fighting the garments in the depth buffer.
 */
export class CharacterAsset {
  /**
   * @param {object} o
   * @param {Record<string, THREE.Vector3>} o.rest     joint name → bind-pose world position
   * @param {Record<string, string|null>} o.parents    joint name → parent joint name
   * @param {string[]} o.order                         joints in depth-first order
   * @param {Map<string, {geometry: THREE.BufferGeometry, material: THREE.Material, joints: string[]}>} o.parts
   */
  constructor({ rest, parents, order, parts }) {
    this.rest = rest;
    this.parents = parents;
    this.order = order;
    this.parts = parts;
    this._sampler = null;
  }

  /** Builds an asset from a loaded glTF. */
  static fromGLTF(gltf) {
    const scene = gltf.scene;
    scene.updateMatrixWorld(true);
    const parts = new Map();
    const rest = {};
    const parents = {};
    const _m = new THREE.Matrix4();
    scene.traverse((o) => {
      if (!o.isSkinnedMesh) return;
      const sk = o.skeleton;
      sk.bones.forEach((bone, i) => {
        if (rest[bone.name]) return;
        // Bind-pose world matrix of the joint = bindMatrix · boneInverse⁻¹.
        _m.copy(sk.boneInverses[i]).invert().premultiply(o.bindMatrix);
        rest[bone.name] = new THREE.Vector3().setFromMatrixPosition(_m);
        parents[bone.name] = bone.parent?.isBone ? bone.parent.name : null;
      });
      // Bind-space geometry: bake the mesh's own bind matrix (identity from Blender).
      const geometry = o.geometry.clone();
      if (!o.bindMatrix.equals(new THREE.Matrix4())) geometry.applyMatrix4(o.bindMatrix);
      parts.set(o.name, { geometry, material: o.material, joints: sk.bones.map((b) => b.name) });
    });
    if (!parts.has('Body')) throw new Error('CharacterAsset: the glTF has no "Body" mesh');
    // Depth-first joint order (parents before children).
    const order = [];
    const visit = (name) => {
      order.push(name);
      for (const [n, p] of Object.entries(parents)) if (p === name) visit(n);
    };
    for (const [n, p] of Object.entries(parents)) if (!p) visit(n);
    return new CharacterAsset({ rest, parents, order, parts });
  }

  /** Joints present in the asset that CharacterRig does not animate (spring chains…). */
  extraJoints(known) {
    return this.order.filter((n) => !known.includes(n));
  }

  /** Height of the top of the head (bind pose). */
  get height() {
    const g = this.parts.get('Body').geometry;
    g.computeBoundingBox();
    return g.boundingBox.max.y;
  }

  // ---------------------------------------------------------------------------
  // Surface sampling (cloth pins)
  // ---------------------------------------------------------------------------
  /**
   * Maps a torso height of the procedural body profile (the space wardrobe
   * items are authored in) to this body, through matching landmarks.
   */
  mapTorsoHeight(y) {
    const r = this.rest;
    const crotch = (r.thighL.y + r.thighR.y) / 2 - 0.07;
    const shoulder = (r.upperArmL.y + r.upperArmR.y) / 2;
    const from = [0.8, 0.98, 1.08, 1.42, 1.49, 1.845];
    const to = [crotch, r.pelvis.y, r.spine.y, shoulder, r.neck.y, this.height];
    if (y <= from[0]) return to[0] + (y - from[0]);
    for (let i = 1; i < from.length; i++) {
      if (y <= from[i]) {
        const k = (y - from[i - 1]) / (from[i] - from[i - 1]);
        return to[i - 1] + (to[i] - to[i - 1]) * k;
      }
    }
    return to[to.length - 1];
  }

  /**
   * Point on the body surface around the torso at height `y` (this body's
   * space) and angle `a` (0 = left side, π/2 = front, 3π/2 = back), pushed
   * out by `inflate`. Returns the bind position and interpolated skin weights
   * as [[jointName, weight], …].
   */
  sampleTorso(y, a, inflate = 0) {
    const s = (this._sampler ??= this._createSampler());
    // Axis: centre of the torso cross-section at this height.
    const pos = s.geometry.attributes.position;
    let cz = 0;
    let n = 0;
    for (let i = 0; i < pos.count; i++) {
      if (Math.abs(pos.getY(i) - y) < 0.012 && Math.abs(pos.getX(i)) < 0.11) {
        cz += pos.getZ(i);
        n++;
      }
    }
    cz = n ? cz / n : 0;
    const dir = new THREE.Vector3(Math.cos(a), 0, Math.sin(a));
    s.raycaster.set(new THREE.Vector3(0, y, cz), dir);
    s.raycaster.far = 0.6;
    const hit = s.raycaster.intersectObject(s.mesh, false)[0];
    const point = hit ? hit.point.clone() : new THREE.Vector3(0, y, cz).addScaledVector(dir, 0.12);
    const normal = hit?.face ? hit.face.normal.clone() : dir.clone();
    if (normal.dot(dir) < 0) normal.negate();
    point.addScaledVector(normal, inflate);
    return { point, weights: hit ? this._weightsAt(hit) : [['pelvis', 1]] };
  }

  _createSampler() {
    const geometry = this.parts.get('Body').geometry;
    const mesh = new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ side: THREE.DoubleSide }));
    mesh.updateMatrixWorld(true);
    return { geometry, mesh, raycaster: new THREE.Raycaster() };
  }

  _weightsAt(hit) {
    const g = this._sampler.geometry;
    const si = g.attributes.skinIndex;
    const sw = g.attributes.skinWeight;
    const joints = this.parts.get('Body').joints;
    const { a, b, c } = hit.face;
    const tri = new THREE.Triangle(
      new THREE.Vector3().fromBufferAttribute(g.attributes.position, a),
      new THREE.Vector3().fromBufferAttribute(g.attributes.position, b),
      new THREE.Vector3().fromBufferAttribute(g.attributes.position, c),
    );
    const bary = tri.getBarycoord(hit.point, new THREE.Vector3());
    const acc = new Map();
    [a, b, c].forEach((v, k) => {
      const f = bary.getComponent(k);
      for (let j = 0; j < 4; j++) {
        const w = sw.getComponent(v, j) * f;
        if (w <= 0) continue;
        const name = joints[si.getComponent(v, j)];
        acc.set(name, (acc.get(name) ?? 0) + w);
      }
    });
    const top = [...acc.entries()].sort((x, y) => y[1] - x[1]).slice(0, 4);
    const sum = top.reduce((s, [, w]) => s + w, 0) || 1;
    return top.map(([n, w]) => [n, w / sum]);
  }
}

/**
 * Loads a character glTF. Resolves to `null` (and logs) when the file is
 * missing or invalid, so the game falls back to the procedural character.
 * @param {string} url
 * @returns {Promise<CharacterAsset|null>}
 */
export async function loadCharacterAsset(url) {
  if (!url) return null;
  try {
    const gltf = await new GLTFLoader().loadAsync(url);
    return CharacterAsset.fromGLTF(gltf);
  } catch (err) {
    console.warn(`[character] "${url}" could not be loaded — using the procedural body.`, err);
    return null;
  }
}

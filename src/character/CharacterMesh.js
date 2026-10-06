import * as THREE from 'three';
import { PALETTE } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { BODY_PROFILES } from './body/BodyProfiles.js';
import { loftSegment, createAccumulator, accumulatorToGeometry, sampleSection, sectionPoint } from './body/Loft.js';

/** Body regions = geometry groups that garments can hide (body masking). */
export const REGIONS = [
  'hips',
  'belly',
  'chest',
  'neck',
  'head',
  'shoulder',
  'upperArm',
  'foreArm',
  'hand',
  'thigh',
  'shin',
  'foot',
];
export const REGION = Object.fromEntries(REGIONS.map((r, i) => [r, i]));

export const BONES = [
  'pelvis',
  'spine',
  'chest',
  'neck',
  'head',
  'upperArmL',
  'foreArmL',
  'handL',
  'upperArmR',
  'foreArmR',
  'handR',
  'thighL',
  'shinL',
  'footL',
  'thighR',
  'shinR',
  'footR',
];
export const BONE_INDEX = Object.fromEntries(BONES.map((b, i) => [b, i]));
const BI = BONE_INDEX;
const PARENT = {
  spine: 'pelvis',
  chest: 'spine',
  neck: 'chest',
  head: 'neck',
  upperArmL: 'chest',
  foreArmL: 'upperArmL',
  handL: 'foreArmL',
  upperArmR: 'chest',
  foreArmR: 'upperArmR',
  handR: 'foreArmR',
  thighL: 'pelvis',
  shinL: 'thighL',
  footL: 'shinL',
  thighR: 'pelvis',
  shinR: 'thighR',
  footR: 'shinR',
};

/** Cloth collision capsules: endpoints in *masculine rest* world coords, attached to a bone. */
const CAPSULES = [
  { name: 'hips', bone: 'pelvis', a: [-0.075, 0.93, -0.005], b: [0.075, 0.93, -0.005] },
  { name: 'belly', bone: 'spine', a: [0, 1.0, 0], b: [0, 1.18, 0.005] },
  { name: 'chest', bone: 'spine', a: [0, 1.2, 0.01], b: [0, 1.35, 0.0] },
  { name: 'shoulders', bone: 'chest', a: [-0.13, 1.4, 0], b: [0.13, 1.4, 0] },
  { name: 'head', bone: 'head', a: [0, 1.7, 0.02], b: [0, 1.71, 0.02] },
  ...['L', 'R'].flatMap((s) => {
    const x = s === 'L' ? 0.095 : -0.095;
    const ax = s === 'L' ? 0.19 : -0.19;
    return [
      { name: 'thigh', bone: `thigh${s}`, a: [x, 0.9, 0], b: [x, 0.5, 0] },
      { name: 'shin', bone: `shin${s}`, a: [x, 0.47, 0], b: [x, 0.08, 0] },
      { name: 'upperArm', bone: `upperArm${s}`, a: [ax, 1.37, -0.01], b: [ax, 1.13, -0.01] },
      { name: 'foreArm', bone: `foreArm${s}`, a: [ax, 1.09, -0.01], b: [ax, 0.87, -0.01] },
    ];
  }),
];

const v3 = (x, y, z) => new THREE.Vector3(x, y, z);
const sm = (a, b, x) => {
  const t = THREE.MathUtils.clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};

function restPositions(profile) {
  const p = {
    pelvis: v3(0, 0.98, 0),
    spine: v3(0, 1.08, 0),
    chest: v3(0, 1.42, 0),
    neck: v3(0, 1.49, 0),
    head: v3(0, 1.59, 0.01),
  };
  for (const [s, sx] of [
    ['L', 1],
    ['R', -1],
  ]) {
    p[`upperArm${s}`] = v3(sx * profile.armX, 1.4, -0.01);
    p[`foreArm${s}`] = v3(sx * profile.armX, 1.11, -0.01);
    p[`hand${s}`] = v3(sx * profile.armX, 0.85, -0.01);
    p[`thigh${s}`] = v3(sx * profile.legX, 0.92, 0);
    p[`shin${s}`] = v3(sx * profile.legX, 0.48, 0);
    p[`foot${s}`] = v3(sx * profile.legX, 0.04, 0);
  }
  return p;
}

const scaleKeys = (keys, s) => keys.map((k) => ({ ...k, w: k.w * s, f: k.f * s, b: k.b * s, dz: k.dz * s }));

/**
 * Segment specs (frames, sections, skin weights, regions) for one profile.
 * Identical structure for both profiles → identical topology → morphable.
 */
function buildSegments(profile, rest) {
  const S = {};
  S.torso = {
    rings: 46,
    radial: 32,
    t0: 0.8,
    t1: 1.52,
    keys: profile.torso,
    capStart: true,
    frame: (t, o, u, v) => (o.set(0, t, 0), u.set(1, 0, 0), v.set(0, 0, 1)),
    weights: (y, a) => {
      const c = Math.cos(a);
      if (y < 1.0) {
        // Lower pelvis follows the legs a little (smoother hip creases).
        const leg = 0.35 * (1 - sm(0.8, 0.96, y)) * Math.abs(c);
        return [
          [BI.pelvis, 1],
          [c >= 0 ? BI.thighL : BI.thighR, leg],
        ];
      }
      if (y < 1.14) {
        const k = sm(1.0, 1.14, y);
        return [
          [BI.pelvis, 1 - k],
          [BI.spine, k],
        ];
      }
      const arm = y > 1.32 && y < 1.47 ? 0.4 * sm(0.7, 0.95, Math.abs(c)) * (1 - sm(1.44, 1.47, y)) : 0;
      const armBone = c >= 0 ? BI.upperArmL : BI.upperArmR;
      if (y < 1.3) return [[BI.spine, 1]];
      if (y < 1.42) {
        const k = sm(1.3, 1.42, y);
        return [
          [BI.spine, 1 - k],
          [BI.chest, k],
          [armBone, arm],
        ];
      }
      if (y < 1.47)
        return [
          [BI.chest, 1],
          [armBone, arm],
        ];
      const k = sm(1.47, 1.52, y);
      return [
        [BI.chest, 1 - k],
        [BI.neck, k],
      ];
    },
    region: (y) => (y < 1.0 ? REGION.hips : y < 1.2 ? REGION.belly : y < 1.44 ? REGION.chest : REGION.neck),
  };
  S.head = {
    rings: 40,
    radial: 28,
    t0: 1.45,
    t1: 1.845,
    keys: profile.head,
    capEnd: true,
    frame: (t, o, u, v) => (o.set(0, t, 0), u.set(1, 0, 0), v.set(0, 0, 1)),
    weights: (y) => {
      if (y < 1.5) {
        const k = sm(1.45, 1.5, y);
        return [
          [BI.chest, 1 - k],
          [BI.neck, k],
        ];
      }
      if (y < 1.555) return [[BI.neck, 1]];
      const k = sm(1.555, 1.62, y);
      return [
        [BI.neck, 1 - k],
        [BI.head, k],
      ];
    },
    region: (y) => (y < 1.575 ? REGION.neck : REGION.head),
  };
  for (const [s, sx] of [
    ['L', 1],
    ['R', -1],
  ]) {
    const sh = rest[`upperArm${s}`];
    const wr = rest[`hand${s}`];
    const hip = rest[`thigh${s}`];
    const ank = rest[`foot${s}`];
    S[`arm${s}`] = {
      rings: 36,
      radial: 20,
      t0: -0.065,
      t1: 0.55,
      keys: profile.arm,
      capStart: true,
      frame: (t, o, u, v) => (o.set(sh.x, sh.y - t, sh.z), u.set(sx, 0, 0), v.set(0, 0, 1)),
      weights: (t) => {
        if (t < 0.04) {
          const k = 0.35 * (1 - sm(-0.065, 0.04, t));
          return [
            [BI[`upperArm${s}`], 1 - k],
            [BI.chest, k],
          ];
        }
        if (t < 0.24) return [[BI[`upperArm${s}`], 1]];
        if (t < 0.32) {
          const k = sm(0.24, 0.32, t);
          return [
            [BI[`upperArm${s}`], 1 - k],
            [BI[`foreArm${s}`], k],
          ];
        }
        if (t < 0.5) return [[BI[`foreArm${s}`], 1]];
        const k = sm(0.5, 0.55, t) * 0.6;
        return [
          [BI[`foreArm${s}`], 1 - k],
          [BI[`hand${s}`], k],
        ];
      },
      region: (t) => (t < 0.12 ? REGION.shoulder : t < 0.24 ? REGION.upperArm : REGION.foreArm),
    };
    S[`hand${s}`] = {
      rings: 20,
      radial: 16,
      t0: -0.01,
      t1: 0.19,
      keys: scaleKeys(profile.hand, profile.handScale),
      capEnd: true,
      frame: (t, o, u, v) => (o.set(wr.x, wr.y - t * profile.handScale, wr.z), u.set(sx, 0, 0), v.set(0, 0, 1)),
      weights: (t) =>
        t < 0.02
          ? [
              [BI[`foreArm${s}`], 1 - sm(-0.01, 0.02, t)],
              [BI[`hand${s}`], sm(-0.01, 0.02, t)],
            ]
          : [[BI[`hand${s}`], 1]],
      region: () => REGION.hand,
    };
    const tStart = new THREE.Vector3(wr.x + sx * 0.006, wr.y - 0.03 * profile.handScale, wr.z + 0.03);
    const tDir = new THREE.Vector3(sx * 0.15, -0.62, 0.77).normalize();
    const tU = new THREE.Vector3(sx, 0, 0).addScaledVector(tDir, -sx * tDir.x).normalize();
    const tV = new THREE.Vector3().crossVectors(tDir, tU).normalize();
    S[`thumb${s}`] = {
      rings: 9,
      radial: 10,
      t0: 0,
      t1: 0.075,
      keys: scaleKeys(
        [
          { t: 0, w: 0.015, f: 0.015, b: 0.015, n: 2, dz: 0 },
          { t: 0.04, w: 0.016, f: 0.015, b: 0.015, n: 2, dz: 0 },
          { t: 0.075, w: 0.007, f: 0.007, b: 0.007, n: 2, dz: 0 },
        ],
        profile.handScale,
      ),
      capEnd: true,
      frame: (t, o, u, v) => (o.copy(tStart).addScaledVector(tDir, t * profile.handScale), u.copy(tU), v.copy(tV)),
      weights: () => [[BI[`hand${s}`], 1]],
      region: () => REGION.hand,
    };
    S[`leg${s}`] = {
      rings: 44,
      radial: 22,
      t0: -0.085,
      t1: 0.9,
      keys: profile.leg,
      capStart: true,
      frame: (t, o, u, v) => (o.set(hip.x, hip.y - t, hip.z), u.set(sx, 0, 0), v.set(0, 0, 1)),
      weights: (t) => {
        if (t < 0.04) {
          const k = 0.45 * (1 - sm(-0.085, 0.04, t));
          return [
            [BI[`thigh${s}`], 1 - k],
            [BI.pelvis, k],
          ];
        }
        if (t < 0.36) return [[BI[`thigh${s}`], 1]];
        if (t < 0.48) {
          const k = sm(0.36, 0.48, t);
          return [
            [BI[`thigh${s}`], 1 - k],
            [BI[`shin${s}`], k],
          ];
        }
        if (t < 0.84) return [[BI[`shin${s}`], 1]];
        const k = sm(0.84, 0.9, t) * 0.4;
        return [
          [BI[`shin${s}`], 1 - k],
          [BI[`foot${s}`], k],
        ];
      },
      region: (t) => (t < 0.42 ? REGION.thigh : REGION.shin),
    };
    S[`foot${s}`] = {
      rings: 22,
      radial: 18,
      t0: -0.08,
      t1: 0.215,
      keys: profile.foot,
      capStart: true,
      capEnd: true,
      frame: (t, o, u, v) => (o.set(ank.x, ank.y, ank.z + t), u.set(sx, 0, 0), v.set(0, 1, 0)),
      weights: () => [[BI[`foot${s}`], 1]],
      region: () => REGION.foot,
    };
  }
  return S;
}

const _m = new THREE.Matrix4();
const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _o = new THREE.Vector3();
const _u = new THREE.Vector3();
const _vv = new THREE.Vector3();
const _sec = {};
const _pt = { x: 0, y: 0 };

/**
 * Modular, skinned, stylised human body.
 *
 *  - One SkinnedMesh lofted from smooth cross-sections (torso, head, arms,
 *    mitten hands + thumbs, legs, chunky feet) — ~7k vertices, clean
 *    low-frequency curves, thick hands/feet, readable silhouette.
 *  - Gender polymorphism: the *feminine* profile is a morph target of the
 *    *masculine* base, and bone rest positions (shoulder/hip width) blend
 *    with the same factor. The morph target is authored in the masculine
 *    bind space (each vertex minus its skin-weighted bone offset), so at any
 *    factor f the rest pose is exactly lerp(masc, fem, f) and linear blend
 *    skinning — hence every animation — keeps working.
 *  - Regions are geometry groups; garments hide the regions they cover.
 *  - Exposes surface sampling + CPU skinning (cloth pins), garment geometry
 *    building on the same skeleton, and profile-aware collision capsules.
 */
export class CharacterMesh {
  /**
   * @param {object} [o]
   * @param {number} [o.femininity] procedural body only: 0 = masculine … 1 = feminine
   * @param {import('./CharacterAsset.js').CharacterAsset|null} [o.asset] authored body (Blender glTF).
   *   Its joint positions become this skeleton's rest pose and its meshes are rebound to it.
   */
  constructor({ femininity = 0, asset = null } = {}) {
    this.asset = asset;
    this.profiles = { A: BODY_PROFILES.masculine, B: BODY_PROFILES.feminine };
    if (asset) {
      const fallback = restPositions(this.profiles.B);
      const rest = Object.fromEntries(BONES.map((b) => [b, asset.rest[b]?.clone() ?? fallback[b]]));
      this.rest = { A: rest, B: rest };
      this.segs = null;
      this.extraBones = asset.extraJoints(BONES);
    } else {
      this.rest = { A: restPositions(this.profiles.A), B: restPositions(this.profiles.B) };
      this.segs = { A: buildSegments(this.profiles.A, this.rest.A), B: buildSegments(this.profiles.B, this.rest.B) };
      this.extraBones = [];
    }
    this.delta = BONES.map((b) => this.rest.B[b].clone().sub(this.rest.A[b]));
    this.femininity = 0;
    this.morphables = [];

    this.root = new THREE.Group();
    this.root.name = 'Character';
    this._createSkeleton();
    if (asset) this._createAssetBody();
    else {
      this._createBody();
      this._createFace();
    }
    this.root.updateMatrixWorld(true);
    this.body.bind(this.skeleton);
    for (const m of this.assetMeshes ?? []) if (m !== this.body) m.bind(this.skeleton, this.body.bindMatrix);
    this.setFemininity(asset ? 1 : femininity);
  }

  /** Whether this body is an authored (glTF) character rather than the procedural loft. */
  get isAuthored() {
    return !!this.asset;
  }

  /** Pelvis rest height (the animator's standing reference). */
  get pelvisHeight() {
    return this.rest.A.pelvis.y;
  }

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------
  _createSkeleton() {
    this.bones = {};
    for (const name of BONES) {
      const b = new THREE.Bone();
      b.name = name;
      this.bones[name] = b;
    }
    for (const name of BONES) {
      const parent = PARENT[name];
      const p = this.rest.A[name];
      if (parent) {
        this.bones[parent].add(this.bones[name]);
        this.bones[name].position.copy(p).sub(this.rest.A[parent]);
      } else {
        this.root.add(this.bones[name]);
        this.bones[name].position.copy(p);
      }
    }
    // Extra authored joints (spring chains…), appended after the animated ones
    // so BONE_INDEX stays valid.
    for (const name of this.extraBones) {
      const b = new THREE.Bone();
      b.name = name;
      const parent = this.asset.parents[name];
      const pRest = this.asset.rest[parent];
      this.bones[parent].add(b);
      b.position.copy(this.asset.rest[name]).sub(pRest);
      this.bones[name] = b;
    }
    this.skeleton = new THREE.Skeleton([...BONES, ...this.extraBones].map((n) => this.bones[n]));
    this.boneIndex = Object.fromEntries(this.skeleton.bones.map((b, i) => [b.name, i]));
  }

  // ---------------------------------------------------------------------------
  // Authored body (glTF)
  // ---------------------------------------------------------------------------
  /** Parts that are always worn (the body itself and the face). */
  static get ASSET_BASE_PARTS() {
    return ['Body', 'Eyes', 'Cornea', 'Eyebrows', 'Eyelashes', 'Teeth', 'Tongue'];
  }

  _createAssetBody() {
    this.assetMeshes = [];
    this.coverMask = new THREE.Vector4(0, 0, 0, 0);
    for (const name of CharacterMesh.ASSET_BASE_PARTS) {
      if (!this.asset.parts.has(name)) continue;
      const mesh = this._assetMesh(name, assetMaterial(name, this.asset.parts.get(name).material, this.coverMask));
      if (name === 'Body') this.body = mesh;
      this.root.add(mesh);
      this.assetMeshes.push(mesh);
    }
    this.skinMaterial = this.body.material;
  }

  /** SkinnedMesh for an asset part, with its joints remapped onto this skeleton (not yet bound). */
  _assetMesh(name, material) {
    const part = this.asset.parts.get(name);
    if (!part) throw new Error(`CharacterMesh: the character asset has no part "${name}"`);
    const geometry = part.geometry.clone();
    const si = geometry.attributes.skinIndex;
    const remap = part.joints.map((j) => this.boneIndex[j] ?? this.boneIndex[this.asset.parents[j]] ?? 0);
    const out = new Uint16Array(si.count * 4);
    for (let i = 0; i < si.count; i++) for (let k = 0; k < 4; k++) out[i * 4 + k] = remap[si.getComponent(i, k)];
    geometry.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(out, 4));
    const mesh = new THREE.SkinnedMesh(geometry, material);
    mesh.name = name;
    mesh.castShadow = name !== 'Eyelashes' && name !== 'Eyebrows';
    mesh.receiveShadow = true;
    mesh.frustumCulled = false;
    return mesh;
  }

  /** Attaches an authored garment / hair part (by glTF node name). */
  attachAssetPart(name, material) {
    const mesh = this._assetMesh(name, material);
    this.root.add(mesh);
    mesh.bind(this.skeleton, this.body.bindMatrix);
    return mesh;
  }

  /** Coverage channels (x, y, z, w) of the body's `_COVER` attribute to hide (0/1 each). */
  setCoverage(mask) {
    if (this.coverMask) this.coverMask.copy(mask);
  }

  _segmentNames() {
    return ['torso', 'head', 'armL', 'armR', 'handL', 'handR', 'thumbL', 'thumbR', 'legL', 'legR', 'footL', 'footR'];
  }

  _createBody() {
    const accA = createAccumulator();
    const accB = createAccumulator();
    for (const name of this._segmentNames()) {
      loftSegment(accA, this.segs.A[name]);
      loftSegment(accB, this.segs.B[name]);
    }
    const { geometry, regionRanges } = this._morphGeometry(accA, accB, REGIONS.length);
    this.regionRanges = regionRanges;

    this.skinMaterial = createStylizedMaterial({
      name: 'Skin',
      color: PALETTE.skin,
      roughness: 0.6,
      wrap: 0.75,
      softness: 0.7,
      rim: 0.3,
      painterly: 0.04,
      painterlyScale: 2,
      cacheKey: 'skin;',
      patch: patchSkin,
    });
    this.hiddenMaterial = new THREE.MeshBasicMaterial({ visible: false });
    this.body = new THREE.SkinnedMesh(geometry, [this.skinMaterial, this.hiddenMaterial]);
    this.body.name = 'Body';
    this.body.castShadow = true;
    this.body.receiveShadow = true;
    this.body.frustumCulled = false;
    this.root.add(this.body);
    this.morphables.push(this.body);
  }

  /**
   * Builds geometry from two accumulators (A = masculine, B = feminine) and
   * stores B as a morph target expressed in A's bind space.
   */
  _morphGeometry(accA, accB, regionCount = 1) {
    const { geometry, regionRanges } = accumulatorToGeometry(accA, regionCount);
    const { geometry: gB } = accumulatorToGeometry(accB, regionCount);
    const pB = gB.attributes.position;
    if (pB.count !== geometry.attributes.position.count) throw new Error('CharacterMesh: profile topology mismatch');
    const si = geometry.attributes.skinIndex;
    const sw = geometry.attributes.skinWeight;
    const corrected = new Float32Array(pB.count * 3);
    for (let i = 0; i < pB.count; i++) {
      _v.fromBufferAttribute(pB, i);
      for (let k = 0; k < 4; k++) {
        const w = sw.getComponent(i, k);
        if (w > 0) _v.addScaledVector(this.delta[si.getComponent(i, k)], -w);
      }
      corrected.set([_v.x, _v.y, _v.z], i * 3);
    }
    geometry.morphAttributes.position = [new THREE.Float32BufferAttribute(corrected, 3)];
    geometry.morphAttributes.normal = [gB.attributes.normal.clone()];
    return { geometry, regionRanges };
  }

  _createFace() {
    const head = this.bones.head;
    const eyeMat = createStylizedMaterial({ name: 'Eye', color: 0x2a2320, roughness: 0.18, rim: 0.05, painterly: 0 });
    const browMat = createStylizedMaterial({ name: 'Brow', color: PALETTE.hair, roughness: 0.8, painterly: 0 });
    const lipMat = createStylizedMaterial({ name: 'Lips', color: 0xb8705f, roughness: 0.45, painterly: 0 });
    const sphere = new THREE.SphereGeometry(1, 14, 10);
    const capsule = new THREE.CapsuleGeometry(1, 1, 3, 8).rotateZ(Math.PI / 2);
    const mk = (geo, mat, name) => {
      const m = new THREE.Mesh(geo, mat);
      m.name = name;
      m.castShadow = false;
      head.add(m);
      return m;
    };
    this.face = {
      eyeL: mk(sphere, eyeMat, 'eyeL'),
      eyeR: mk(sphere, eyeMat, 'eyeR'),
      browL: mk(capsule, browMat, 'browL'),
      browR: mk(capsule, browMat, 'browR'),
      nose: mk(sphere, this.skinMaterial, 'nose'),
      earL: mk(sphere, this.skinMaterial, 'earL'),
      earR: mk(sphere, this.skinMaterial, 'earR'),
      lips: mk(capsule, lipMat, 'lips'),
    };
  }

  _applyFace(f) {
    const A = this.profiles.A.face;
    const B = this.profiles.B.face;
    const L = (a, b) => a + (b - a) * f;
    const F = this.face; // features are authored relative to the head bone
    const eye = { x: L(A.eye.x, B.eye.x), y: L(A.eye.y, B.eye.y), z: L(A.eye.z, B.eye.z), r: L(A.eye.r, B.eye.r) };
    F.eyeL.position.set(eye.x, eye.y, eye.z);
    F.eyeR.position.set(-eye.x, eye.y, eye.z);
    F.eyeL.scale.set(eye.r, eye.r * 1.25, eye.r * 0.6);
    F.eyeR.scale.copy(F.eyeL.scale);
    const brow = {
      x: L(A.brow.x, B.brow.x),
      y: L(A.brow.y, B.brow.y),
      z: L(A.brow.z, B.brow.z),
      len: L(A.brow.len, B.brow.len),
      r: L(A.brow.r, B.brow.r),
      tilt: L(A.brow.tilt, B.brow.tilt),
    };
    for (const [m, sx] of [
      [F.browL, 1],
      [F.browR, -1],
    ]) {
      m.position.set(sx * brow.x, brow.y, brow.z);
      m.scale.set(brow.r, brow.len / 2, brow.r);
      m.rotation.set(0, sx * -0.3, sx * brow.tilt);
    }
    const nose = {
      y: L(A.nose.y, B.nose.y),
      z: L(A.nose.z, B.nose.z),
      len: L(A.nose.len, B.nose.len),
      r: L(A.nose.r, B.nose.r),
    };
    F.nose.position.set(0, nose.y, nose.z);
    F.nose.scale.set(nose.r * 0.8, nose.len * 0.6, nose.r);
    F.nose.rotation.x = 0.35;
    const ear = { x: L(A.ear.x, B.ear.x), y: L(A.ear.y, B.ear.y), z: L(A.ear.z, B.ear.z) };
    const es = A.ear.s.map((s, i) => L(s, B.ear.s[i]));
    F.earL.position.set(ear.x, ear.y, ear.z);
    F.earR.position.set(-ear.x, ear.y, ear.z);
    F.earL.scale.set(...es);
    F.earR.scale.set(...es);
    const lips = {
      y: L(A.lips.y, B.lips.y),
      z: L(A.lips.z, B.lips.z),
      w: L(A.lips.w, B.lips.w),
      r: L(A.lips.r, B.lips.r),
    };
    F.lips.position.set(0, lips.y, lips.z);
    F.lips.scale.set(lips.r, lips.w / 2, lips.r * 0.8);
    F.lips.material.color.setHex(PALETTE.skin).lerp(_c.setHex(0xb8705f), 0.25 + 0.6 * f);
  }

  // ---------------------------------------------------------------------------
  // Profile morph
  // ---------------------------------------------------------------------------
  /** 0 = masculine, 1 = feminine; any value in between blends smoothly. */
  setFemininity(f) {
    f = THREE.MathUtils.clamp(f, 0, 1);
    this.femininity = f;
    if (this.asset) return; // authored bodies have a single, fixed profile
    for (const m of this.morphables) {
      if (!m.morphTargetInfluences) m.updateMorphTargets();
      m.morphTargetInfluences[0] = f;
    }
    // Bone rest positions blend with the same factor (except the pelvis, which
    // the animator drives).
    for (const name of BONES) {
      const parent = PARENT[name];
      if (!parent) continue;
      _v.lerpVectors(this.rest.A[name], this.rest.B[name], f);
      _w.lerpVectors(this.rest.A[parent], this.rest.B[parent], f);
      this.bones[name].position.subVectors(_v, _w);
    }
    this._applyFace(f);
  }

  // ---------------------------------------------------------------------------
  // Body masking
  // ---------------------------------------------------------------------------
  /** Hides body regions (by name) covered by garments; shows the rest. */
  setHiddenRegions(names) {
    if (this.asset) return; // authored bodies use coverage channels (setCoverage)
    const hidden = new Set(names);
    for (const g of this.body.geometry.groups) g.materialIndex = hidden.has(REGIONS[g.region]) ? 1 : 0;
  }

  // ---------------------------------------------------------------------------
  // Garment support
  // ---------------------------------------------------------------------------
  /**
   * Lofts garment geometry over body segments with the same skinning and the
   * same morph scheme as the body (so garments follow both the animation and
   * the masculine↔feminine morph).
   * @param {object[]} parts [{ segment, t0, t1, rings, radial?, inflate, capStart?, capEnd? }]
   */
  buildGarmentGeometry(parts) {
    if (this.asset) throw new Error('CharacterMesh: lofted garments need the procedural body');
    const accA = createAccumulator();
    const accB = createAccumulator();
    for (const part of parts) {
      for (const [acc, segs] of [
        [accA, this.segs.A],
        [accB, this.segs.B],
      ]) {
        const base = segs[part.segment] ?? part.custom?.(segs);
        loftSegment(acc, {
          ...base,
          ...part.override,
          t0: part.t0 ?? base.t0,
          t1: part.t1 ?? base.t1,
          rings: part.rings ?? base.rings,
          radial: part.radial ?? base.radial,
          inflate: part.inflate ?? 0,
          capStart: part.capStart ?? false,
          capEnd: part.capEnd ?? false,
          region: () => 0,
        });
      }
    }
    return this._morphGeometry(accA, accB, 1).geometry;
  }

  /** Wraps garment geometry in a SkinnedMesh bound to this skeleton. */
  attachGarment(geometry, material, name = 'Garment') {
    const mesh = new THREE.SkinnedMesh(geometry, material);
    mesh.name = name;
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    mesh.frustumCulled = false;
    this.root.add(mesh);
    mesh.bind(this.skeleton, this.body.bindMatrix);
    mesh.updateMorphTargets();
    mesh.morphTargetInfluences[0] = this.femininity;
    this.morphables.push(mesh);
    return mesh;
  }

  detachGarment(mesh) {
    mesh.removeFromParent();
    this.morphables.splice(this.morphables.indexOf(mesh), 1);
    mesh.geometry.dispose();
  }

  /** Skin weights for a body-segment surface point (same functions as the body). */
  _weights(segment, t, a) {
    const w = this.segs.A[segment].weights(t, a).slice(0, 4);
    const sum = w.reduce((s, [, x]) => s + x, 0);
    return w.map(([b, x]) => [b, x / sum]);
  }

  /**
   * Samples a point on a body segment for both profiles (bind space).
   * Use with `skinPoint` to get its animated world position every frame.
   */
  sampleSurface(segment, t, a, inflate = 0) {
    if (this.asset) {
      if (segment !== 'torso') throw new Error(`CharacterMesh: authored bodies only sample the torso (got "${segment}")`);
      const { point, weights } = this.asset.sampleTorso(this.asset.mapTorsoHeight(t), a, inflate);
      return { a: point, b: point.clone(), weights: weights.map(([n, w]) => [this.boneIndex[n] ?? 0, w]) };
    }
    const pts = ['A', 'B'].map((P) => {
      const seg = this.segs[P][segment];
      seg.frame(t, _o, _u, _vv);
      sampleSection(seg.keys, t, _sec);
      sectionPoint(_sec, a, inflate, _pt);
      return new THREE.Vector3().copy(_o).addScaledVector(_u, _pt.x).addScaledVector(_vv, _pt.y);
    });
    const weights = this._weights(segment, t, a);
    for (const [b, w] of weights) pts[1].addScaledVector(this.delta[b], -w);
    return { a: pts[0], b: pts[1], weights };
  }

  /** Current world position of a sampled surface point (CPU linear blend skinning). */
  skinPoint(sample, out) {
    _v.lerpVectors(sample.a, sample.b, this.femininity);
    out.set(0, 0, 0);
    const bind = this.body.bindMatrix;
    for (const [b, w] of sample.weights) {
      _m.multiplyMatrices(this.skeleton.bones[b].matrixWorld, this.skeleton.boneInverses[b]).multiply(bind);
      out.addScaledVector(_w.copy(_v).applyMatrix4(_m), w);
    }
    return out;
  }

  /**
   * World-space collision capsules sized for the current profile.
   * @param {number} [inflate] extra radius (cloth layer offset)
   * @returns {{name:string, a:THREE.Vector3, b:THREE.Vector3, r:number}[]}
   */
  getCapsules(out = [], inflate = 0) {
    if (this.asset) return this._assetCapsules(out, inflate);
    const f = this.femininity;
    CAPSULES.forEach((c, i) => {
      const cap = (out[i] ??= { name: c.name, a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0 });
      const bone = this.bones[c.bone];
      const rest = this.rest.A[c.bone];
      cap.a.set(c.a[0] - rest.x, c.a[1] - rest.y, c.a[2] - rest.z).applyMatrix4(bone.matrixWorld);
      cap.b.set(c.b[0] - rest.x, c.b[1] - rest.y, c.b[2] - rest.z).applyMatrix4(bone.matrixWorld);
      const rA = this.profiles.A.capsules[c.name];
      const rB = this.profiles.B.capsules[c.name];
      cap.r = rA + (rB - rA) * f + inflate;
    });
    out.length = CAPSULES.length;
    return out;
  }

  /** Capsules derived from the authored skeleton's joints (same names as the procedural set). */
  _assetCapsules(out, inflate) {
    if (!this._capDefs) {
      const R = this.rest.A;
      const v = (x, y, z) => new THREE.Vector3(x, y, z);
      const lerp = (a, b, k) => a.clone().lerp(b, k);
      const shoulderY = (R.upperArmL.y + R.upperArmR.y) / 2;
      const hipX = Math.abs(R.thighL.x) * 0.8;
      const z = R.spine.z;
      this._capDefs = [
        { name: 'hips', bone: 'pelvis', a: v(-hipX, R.pelvis.y - 0.03, z - 0.01), b: v(hipX, R.pelvis.y - 0.03, z - 0.01), r: 0.112 },
        { name: 'belly', bone: 'spine', a: v(0, R.spine.y - 0.02, z), b: v(0, lerp(R.spine, R.upperArmL, 0.35).y, z), r: 0.1 },
        { name: 'chest', bone: 'chest', a: v(0, R.chest.y + 0.05, z + 0.01), b: v(0, shoulderY - 0.05, z), r: 0.112 },
        { name: 'shoulders', bone: 'chest', a: v(-0.12, shoulderY + 0.01, z), b: v(0.12, shoulderY + 0.01, z), r: 0.072 },
        { name: 'head', bone: 'head', a: v(0, R.head.y + 0.09, R.head.z + 0.02), b: v(0, R.head.y + 0.1, R.head.z + 0.02), r: 0.1 },
        ...['L', 'R'].flatMap((s) => [
          { name: 'thigh', bone: `thigh${s}`, a: R[`thigh${s}`].clone(), b: lerp(R[`thigh${s}`], R[`shin${s}`], 0.92), r: 0.082 },
          { name: 'shin', bone: `shin${s}`, a: R[`shin${s}`].clone(), b: lerp(R[`shin${s}`], R[`foot${s}`], 0.95), r: 0.052 },
          { name: 'upperArm', bone: `upperArm${s}`, a: R[`upperArm${s}`].clone(), b: lerp(R[`upperArm${s}`], R[`foreArm${s}`], 0.92), r: 0.048 },
          { name: 'foreArm', bone: `foreArm${s}`, a: R[`foreArm${s}`].clone(), b: lerp(R[`foreArm${s}`], R[`hand${s}`], 0.95), r: 0.038 },
        ]),
      ];
    }
    this._capDefs.forEach((c, i) => {
      const cap = (out[i] ??= { name: c.name, a: new THREE.Vector3(), b: new THREE.Vector3(), r: 0 });
      const bone = this.bones[c.bone];
      const rest = this.rest.A[c.bone];
      cap.a.copy(c.a).sub(rest).applyMatrix4(bone.matrixWorld);
      cap.b.copy(c.b).sub(rest).applyMatrix4(bone.matrixWorld);
      cap.r = c.r + inflate;
    });
    out.length = this._capDefs.length;
    return out;
  }
}

/**
 * Stylised materials for authored character parts, keeping the glTF's baked
 * textures (albedo, normal, roughness) and the game's lighting model.
 */
function assetMaterial(name, src, coverMask) {
  const tex = (k) => src?.[k] ?? null;
  const common = { name: `Asset:${name}`, map: tex('map'), color: src?.color?.getHex?.() ?? 0xffffff };
  let m;
  if (name === 'Body') {
    m = createStylizedMaterial({
      ...common,
      roughness: 0.55,
      wrap: 0.62,
      softness: 0.62,
      rim: 0.22,
      painterly: 0.0,
      uniforms: { uCoverMask: { value: coverMask } },
      cacheKey: 'asset-skin;cover;',
      patch: patchCoverage,
    });
  } else if (name === 'Eyes') {
    m = createStylizedMaterial({ ...common, roughness: 0.35, wrap: 0.5, rim: 0.0, painterly: 0, envMapIntensity: 0.6 });
  } else if (name === 'Cornea') {
    // Clear, wet cornea: only its specular highlight shows.
    m = createStylizedMaterial({
      ...common,
      map: null,
      color: 0xffffff,
      roughness: 0.03,
      rim: 0,
      painterly: 0,
      transparent: true,
      opacity: 0.08,
      envMapIntensity: 1.4,
    });
    m.depthWrite = false;
  } else if (name === 'Eyebrows' || name === 'Eyelashes' || name === 'Hair') {
    const hair = name === 'Hair';
    m = createStylizedMaterial({
      ...common,
      // Brows/lashes textures are dark-on-alpha: tint them towards the hair colour.
      color: hair ? 0xffffff : name === 'Eyebrows' ? 0xa07a62 : 0x3a2a22,
      roughness: hair ? 0.42 : 0.7,
      wrap: 0.6,
      rim: hair ? 0.35 : 0.05,
      painterly: 0,
      alphaTest: hair ? 0.6 : 0,
      side: THREE.DoubleSide,
    });
    // Brows and lashes are fine, soft strands: alpha-blend them (they sit on the
    // skin, so sorting never matters) instead of a hard-cut band.
    if (!hair) {
      m.transparent = true;
      m.depthWrite = false;
      m.alphaTest = 0.02;
    }
  } else {
    m = createStylizedMaterial({ ...common, roughness: src?.roughness ?? 0.6, metalness: src?.metalness ?? 0, painterly: 0 });
  }
  if (src?.normalMap) {
    m.normalMap = src.normalMap;
    m.normalScale.copy(src.normalScale ?? new THREE.Vector2(1, 1));
  }
  if (src?.roughnessMap) m.roughnessMap = src.roughnessMap;
  return m;
}

/** Drops skin fragments covered by the current outfit (see CharacterAsset `_COVER`). */
function patchCoverage(shader) {
  shader.vertexShader = shader.vertexShader
    .replace('#include <common>', '#include <common>\nattribute vec4 _cover;\nvarying vec4 vCover;')
    .replace('#include <begin_vertex>', '#include <begin_vertex>\nvCover = _cover;');
  shader.fragmentShader = shader.fragmentShader
    .replace('#include <common>', '#include <common>\nuniform vec4 uCoverMask;\nvarying vec4 vCover;')
    .replace(
      '#include <clipping_planes_fragment>',
      '#include <clipping_planes_fragment>\nif (dot(vCover, uCoverMask) > 0.5) discard;',
    );
}

const _c = new THREE.Color();

/**
 * Skin tone variation on the body-surface coordinates (aBodyUV = angle/2π,
 * segment t; the head's t is world height): a soft blush over the cheeks
 * and a warmer tint on the nose tip and ears' height band.
 */
function patchSkin(shader) {
  shader.vertexShader = shader.vertexShader
    .replace('#include <common>', '#include <common>\nattribute vec2 aBodyUV;\nvarying vec2 vSkinUV;')
    .replace('#include <begin_vertex>', '#include <begin_vertex>\nvSkinUV = aBodyUV;');
  shader.fragmentShader = shader.fragmentShader
    .replace('#include <common>', '#include <common>\nvarying vec2 vSkinUV;')
    .replace(
      '#include <color_fragment>',
      /* glsl */ `#include <color_fragment>
      {
        float a = vSkinUV.x * 6.2831853;
        float y = vSkinUV.y;
        float cheek = 0.0;
        for (int s = -1; s <= 1; s += 2) {
          float da = a - (1.5708 + float(s) * 0.62);
          float dy = (y - 1.655) / 0.024;
          cheek += exp(-da * da / 0.045 - dy * dy);
        }
        float da = a - 1.5708;
        float nose = exp(-da * da / 0.02 - pow((y - 1.675) / 0.018, 2.0));
        float flush = clamp(cheek * 0.6 + nose * 0.3, 0.0, 1.0);
        diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(1.06, 0.8, 0.78), flush);
      }`,
    );
}

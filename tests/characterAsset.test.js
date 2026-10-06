import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { CharacterAsset } from '../src/character/CharacterAsset.js';
import { CharacterMesh, BONES } from '../src/character/CharacterMesh.js';
import { CharacterRig } from '../src/character/CharacterRig.js';
import { Wardrobe } from '../src/character/Wardrobe.js';

/**
 * Authored-character path (Blender glTF → CharacterAsset → CharacterMesh)
 * against a synthetic asset with the heroine's real joint layout. Runs
 * without physics or a renderer.
 */

// Bind-pose joints of the exported heroine (three.js space: +Y up, +Z forward, +X left).
const JOINTS = {
  pelvis: [0, 0.882, 0.022],
  spine: [0, 1.019, -0.003],
  chest: [0, 1.108, 0.011],
  neck: [0, 1.42, -0.001],
  head: [0, 1.538, 0.042],
  upperArmL: [0.164, 1.33, 0.022],
  foreArmL: [0.193, 1.087, 0.027],
  handL: [0.22, 0.863, 0.031],
  upperArmR: [-0.164, 1.33, 0.022],
  foreArmR: [-0.193, 1.087, 0.027],
  handR: [-0.22, 0.863, 0.031],
  thighL: [0.097, 0.869, 0.017],
  shinL: [0.097, 0.482, 0.017],
  footL: [0.097, 0.065, 0.017],
  thighR: [-0.097, 0.869, 0.017],
  shinR: [-0.097, 0.482, 0.017],
  footR: [-0.097, 0.065, 0.017],
  hair0: [0, 1.565, -0.095],
  hair1: [0, 1.49, -0.107],
  hair2: [0, 1.415, -0.102],
  hair3: [0, 1.345, -0.088],
};
const PARENTS = {
  pelvis: null,
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
  hair0: 'head',
  hair1: 'hair0',
  hair2: 'hair1',
  hair3: 'hair2',
};
// The glTF skeleton's joint order deliberately differs from the game's.
const GLTF_ORDER = ['pelvis', 'spine', 'chest', 'neck', 'head', 'hair0', 'hair1', 'hair2', 'hair3',
  'upperArmL', 'foreArmL', 'handL', 'upperArmR', 'foreArmR', 'handR', 'thighL', 'shinL', 'footL', 'thighR', 'shinR', 'footR'];

/** A coarse skinned "body": a torso cylinder + limb cylinders, each vertex bound to its nearest joint. */
function bodyGeometry() {
  const parts = [
    new THREE.CylinderGeometry(0.15, 0.17, 0.62, 24, 12).translate(0, 1.1, 0.01), // torso
    new THREE.SphereGeometry(0.1, 16, 12).translate(0, 1.62, 0.03), // head
    ...[1, -1].flatMap((s) => [
      new THREE.CylinderGeometry(0.07, 0.05, 0.8, 12, 10).translate(s * 0.097, 0.47, 0.017), // leg
      new THREE.CylinderGeometry(0.045, 0.035, 0.5, 10, 8).translate(s * 0.19, 1.08, 0.025), // arm
    ]),
  ];
  const merged = mergeGeometries(parts);
  const pos = merged.attributes.position;
  const names = GLTF_ORDER.filter((n) => !n.startsWith('hair'));
  const si = new Uint16Array(pos.count * 4);
  const sw = new Float32Array(pos.count * 4);
  const cover = new Float32Array(pos.count * 4);
  const p = new THREE.Vector3();
  for (let i = 0; i < pos.count; i++) {
    p.fromBufferAttribute(pos, i);
    let best = 0;
    let bd = Infinity;
    names.forEach((n) => {
      const d = p.distanceToSquared(new THREE.Vector3(...JOINTS[n]));
      if (d < bd) (bd = d), (best = GLTF_ORDER.indexOf(n));
    });
    si[i * 4] = best;
    sw[i * 4] = 1;
    cover[i * 4] = p.y < 1.4 && p.y > 0.3 ? 1 : 0; // "clothed" between shins and shoulders
  }
  merged.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(si, 4));
  merged.setAttribute('skinWeight', new THREE.Float32BufferAttribute(sw, 4));
  merged.setAttribute('_cover', new THREE.Float32BufferAttribute(cover, 4));
  return merged;
}

function mergeGeometries(geos) {
  const out = new THREE.BufferGeometry();
  const P = [];
  const N = [];
  const U = [];
  const I = [];
  let base = 0;
  for (const g of geos) {
    const gi = g.index ? g.index.array : [...Array(g.attributes.position.count).keys()];
    P.push(...g.attributes.position.array);
    N.push(...g.attributes.normal.array);
    U.push(...g.attributes.uv.array);
    I.push(...Array.from(gi, (x) => x + base));
    base += g.attributes.position.count;
  }
  out.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(N, 3));
  out.setAttribute('uv', new THREE.Float32BufferAttribute(U, 2));
  out.setIndex(I);
  return out;
}

/** Rebuilds what GLTFLoader produces: bones with arbitrary rest rotations + skinned meshes. */
function fakeGLTF() {
  const scene = new THREE.Group();
  const bones = {};
  for (const n of GLTF_ORDER) {
    const b = new THREE.Bone();
    b.name = n;
    bones[n] = b;
  }
  // Blender-style bone frames: non-identity rest rotations must not matter.
  const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(0.3, -0.7, 1.1));
  for (const n of GLTF_ORDER) {
    const b = bones[n];
    const world = new THREE.Matrix4().compose(new THREE.Vector3(...JOINTS[n]), q, new THREE.Vector3(1, 1, 1));
    if (PARENTS[n]) {
      bones[PARENTS[n]].add(b);
      const pw = new THREE.Matrix4().compose(new THREE.Vector3(...JOINTS[PARENTS[n]]), q, new THREE.Vector3(1, 1, 1));
      world.premultiply(pw.invert());
    } else scene.add(b);
    world.decompose(b.position, b.quaternion, b.scale);
  }
  scene.updateMatrixWorld(true);
  const skeleton = new THREE.Skeleton(GLTF_ORDER.map((n) => bones[n]));
  const make = (name, geometry, color) => {
    const m = new THREE.SkinnedMesh(geometry, new THREE.MeshStandardMaterial({ color }));
    m.name = name;
    scene.add(m);
    m.bind(skeleton, new THREE.Matrix4());
    return m;
  };
  const body = bodyGeometry();
  make('Body', body, 0xe0b090);
  // Garments/hair: offset copies of parts of the body are enough for the wardrobe.
  for (const n of ['Tunic', 'Belt', 'Buckle', 'Trousers', 'Boots', 'Soles', 'Hair', 'Eyes', 'Cornea']) {
    const g = body.clone();
    g.deleteAttribute('_cover');
    make(n, g, 0x888888);
  }
  return { scene };
}

const asset = CharacterAsset.fromGLTF(fakeGLTF());

test('CharacterAsset: joint rest positions and hierarchy come from the glTF skeleton', () => {
  for (const [n, p] of Object.entries(JOINTS)) {
    assert.ok(asset.rest[n].distanceTo(new THREE.Vector3(...p)) < 1e-5, `${n} rest position`);
    assert.equal(asset.parents[n], PARENTS[n], `${n} parent`);
  }
  assert.deepEqual(asset.extraJoints(BONES), ['hair0', 'hair1', 'hair2', 'hair3']);
  assert.ok(Math.abs(asset.height - 1.72) < 0.01);
});

test('CharacterMesh(asset): rebinding reproduces the authored bind pose exactly', () => {
  const mesh = new CharacterMesh({ asset });
  assert.ok(mesh.isAuthored);
  assert.ok(Math.abs(mesh.pelvisHeight - 0.882) < 1e-6);
  assert.equal(mesh.skeleton.bones.length, BONES.length + 4);
  assert.deepEqual(mesh.skeleton.bones.slice(0, BONES.length).map((b) => b.name), BONES);
  for (const b of mesh.skeleton.bones) assert.ok(b.quaternion.equals(new THREE.Quaternion()), 'identity rest rotations');
  mesh.root.updateMatrixWorld(true);
  const src = asset.parts.get('Body').geometry.attributes.position;
  const v = new THREE.Vector3();
  let maxErr = 0;
  for (let i = 0; i < src.count; i += 7) {
    v.fromBufferAttribute(mesh.body.geometry.attributes.position, i);
    mesh.body.applyBoneTransform(i, v);
    maxErr = Math.max(maxErr, v.distanceTo(new THREE.Vector3().fromBufferAttribute(src, i)));
  }
  assert.ok(maxErr < 1e-5, `rest-pose skinning error ${maxErr}`);
});

test('CharacterMesh(asset): joints rotate about world-aligned axes at the authored joints', () => {
  const mesh = new CharacterMesh({ asset });
  mesh.bones.thighL.rotation.set(-Math.PI / 2, 0, 0); // leg forward (+Z)
  mesh.root.updateMatrixWorld(true);
  const knee = mesh.bones.shinL.getWorldPosition(new THREE.Vector3());
  const hip = new THREE.Vector3(...JOINTS.thighL);
  const len = hip.y - JOINTS.shinL[1];
  assert.ok(Math.abs(knee.y - hip.y) < 1e-4, 'knee at hip height');
  assert.ok(Math.abs(knee.z - (hip.z + len)) < 1e-4, 'knee in front of the hip');
});

test('CharacterRig(asset): poses use the authored proportions', () => {
  const rig = new CharacterRig({ asset });
  rig.update(0);
  assert.ok(Math.abs(rig.joints.pelvis.position.y - 0.882) < 0.01, 'standing pelvis height');
  assert.ok(Math.abs(rig.proportions.kneelY - (0.869 - 0.482 + 0.12)) < 1e-3);
  rig.playPose('kneel', 0);
  rig.update(0.016);
  assert.ok(Math.abs(rig.joints.pelvis.position.y - rig.proportions.kneelY) < 1e-3);
  rig.setFemininity?.(0); // no-op API compatibility
  rig.body.setFemininity(0);
  assert.equal(rig.body.femininity, 0);
});

test('CharacterMesh(asset): capsules and torso samples follow the authored body', () => {
  const mesh = new CharacterMesh({ asset });
  mesh.root.updateMatrixWorld(true);
  const caps = mesh.getCapsules([]);
  const byName = (n) => caps.filter((c) => c.name === n);
  assert.equal(byName('thigh').length, 2);
  assert.equal(byName('shin').length, 2);
  for (const n of ['hips', 'belly', 'chest', 'shoulders', 'head', 'upperArm', 'foreArm']) assert.ok(byName(n).length, n);
  const thigh = byName('thigh')[0];
  assert.ok(thigh.a.distanceTo(new THREE.Vector3(...JOINTS.thighL)) < 1e-6 || thigh.a.distanceTo(new THREE.Vector3(...JOINTS.thighR)) < 1e-6);
  // Cloak pin height (procedural torso t = 1.43, just under the shoulders) maps to the authored shoulders.
  const y = asset.mapTorsoHeight(1.42);
  assert.ok(Math.abs(y - 1.33) < 1e-6);
  const s = mesh.sampleSurface('torso', 1.43, (3 * Math.PI) / 2, 0.03); // back of the shoulders
  const sum = s.weights.reduce((a, [, w]) => a + w, 0);
  assert.ok(Math.abs(sum - 1) < 1e-6);
  assert.ok(s.a.z < 0, 'behind the body');
  const out = mesh.skinPoint(s, new THREE.Vector3());
  assert.ok(out.distanceTo(s.a) < 1e-5, 'skinPoint at rest = bind position');
  assert.throws(() => mesh.buildGarmentGeometry([]), /procedural body/);
});

test('Wardrobe(asset): authored explorer outfit, coverage channel, spring ponytail, shared cloth', () => {
  const rig = new CharacterRig({ asset });
  const parent = new THREE.Group();
  parent.add(rig.root);
  rig.update(0);
  const wardrobe = new Wardrobe({ mesh: rig.body, wind: null, worldParent: parent });
  assert.deepEqual(wardrobe.outfitNames, ['explorer']);
  wardrobe.equipOutfit('explorer');
  const names = [...wardrobe.items.keys()].sort();
  assert.deepEqual(names, ['cloak', 'explorerBelt', 'explorerBoots', 'explorerTrousers', 'explorerTunic', 'heroineHair']);
  assert.deepEqual(rig.body.coverMask.toArray(), [1, 0, 0, 0]);
  const meshes = new Set();
  rig.root.traverse((o) => o.isSkinnedMesh && meshes.add(o.name));
  for (const n of ['Body', 'Tunic', 'Belt', 'Buckle', 'Trousers', 'Boots', 'Soles', 'Hair', 'Eyes', 'Cornea']) assert.ok(meshes.has(n), n);
  // Ponytail swings under gravity when the head turns, then the outfit is removable.
  const hair = wardrobe.items.get('heroineHair');
  assert.ok(hair.spring && hair.spring.joints.length === 4);
  for (let i = 0; i < 30; i++) {
    rig.joints.head.rotation.y = 0.8 * Math.sin(i * 0.3);
    rig.root.updateMatrixWorld(true);
    wardrobe.update(1 / 60, 0);
  }
  assert.ok(!rig.body.bones.hair0.quaternion.equals(new THREE.Quaternion()), 'spring moved the ponytail');
  for (const v of wardrobe.items.get('cloak').cloth.positions ?? []) assert.ok(Number.isFinite(v));
  wardrobe.unequip('heroineHair');
  assert.ok(rig.body.bones.hair0.quaternion.equals(new THREE.Quaternion()), 'spring joints back at rest');
  wardrobe.unequip('explorerTunic');
  wardrobe.unequip('explorerTrousers');
  wardrobe.unequip('explorerBelt');
  wardrobe.unequip('explorerBoots');
  assert.deepEqual(rig.body.coverMask.toArray(), [0, 0, 0, 0]);
  // Unknown procedural outfits are ignored for the authored body (no crash).
  wardrobe.equipOutfit('bikini');
  assert.equal(wardrobe.outfit, 'explorer');
});

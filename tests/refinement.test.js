import { test } from 'node:test';
import assert from 'node:assert/strict';
import { THREE, lcg, createPhysics } from './helpers.js';
import { Sand } from '../src/environment/Sand.js';
import { sandHeight } from '../src/environment/Terrain.js';
import { CityBuilder, cityGroundHeight } from '../src/environment/CityBuilder.js';
import { WindSystem } from '../src/environment/WindSystem.js';
import { InteractionManager } from '../src/interaction/InteractionManager.js';
import { VehicleSystem } from '../src/vehicle/VehicleSystem.js';
import { CharacterController } from '../src/character/CharacterController.js';
import { WORLD } from '../src/config.js';
import { CharacterMesh, REGIONS, BONES } from '../src/character/CharacterMesh.js';
import { Wardrobe, OUTFITS, WARDROBE_ITEMS } from '../src/character/Wardrobe.js';
import { createAccumulator, loftSegment, accumulatorToGeometry } from '../src/character/body/Loft.js';
import { ParticlePool, ParticleSystem, PARTICLE_TYPES } from '../src/vfx/ParticleSystem.js';
import { gradeColor, createJusantLUT } from '../src/lighting/JusantLUT.js';

/** Raw (un-corrected) feminine rest positions, lofted exactly like the body. */
function feminineRest(mesh) {
  const acc = createAccumulator();
  for (const name of mesh._segmentNames()) loftSegment(acc, mesh.segs.B[name]);
  return accumulatorToGeometry(acc, REGIONS.length).geometry.attributes.position;
}

test('CharacterMesh: masculine↔feminine morph is exact under skinning', () => {
  const mesh = new CharacterMesh({ femininity: 0 });
  const rawA = mesh.body.geometry.attributes.position.clone();
  const rawB = feminineRest(mesh);
  const p = new THREE.Vector3();
  const a = new THREE.Vector3();
  const b = new THREE.Vector3();
  for (const f of [0, 0.37, 1]) {
    mesh.setFemininity(f);
    mesh.root.updateMatrixWorld(true);
    let maxErr = 0;
    for (let i = 0; i < rawA.count; i += 7) {
      mesh.body.getVertexPosition(i, p); // morph + linear blend skinning (CPU mirror of the GPU path)
      a.fromBufferAttribute(rawA, i);
      b.fromBufferAttribute(rawB, i);
      maxErr = Math.max(maxErr, p.distanceTo(a.lerp(b, f)));
    }
    assert.ok(maxErr < 1e-5, `f=${f}: rest pose deviates from the profile blend by ${maxErr} m`);
  }
});

test('CharacterMesh: regions are geometry groups that garments can hide', () => {
  const mesh = new CharacterMesh();
  const groups = mesh.body.geometry.groups;
  assert.equal(groups.length, REGIONS.length);
  const tris = groups.reduce((s, g) => s + g.count / 3, 0);
  assert.equal(tris, mesh.body.geometry.index.count / 3);
  mesh.setHiddenRegions(['belly', 'thigh']);
  for (const g of groups) {
    const hidden = REGIONS[g.region] === 'belly' || REGIONS[g.region] === 'thigh';
    assert.equal(g.materialIndex, hidden ? 1 : 0);
  }
  mesh.setHiddenRegions([]);
  assert.ok(groups.every((g) => g.materialIndex === 0));
});

test('CharacterMesh: surface samples follow the animated skeleton', () => {
  const mesh = new CharacterMesh({ femininity: 1 });
  const sample = mesh.sampleSurface('torso', 1.3, Math.PI / 2, 0); // front of the chest
  const rest = mesh.skinPoint(sample, new THREE.Vector3());
  mesh.root.updateMatrixWorld(true);
  const rest2 = mesh.skinPoint(sample, new THREE.Vector3());
  assert.ok(rest.distanceTo(rest2) < 1e-6);
  // Bend the spine forward: the chest point must move forward and down.
  mesh.bones.spine.rotation.x = 0.5;
  mesh.root.updateMatrixWorld(true);
  const bent = mesh.skinPoint(sample, new THREE.Vector3());
  assert.ok(bent.z > rest.z + 0.03 && bent.y < rest.y - 0.01, 'chest point did not follow the spine');
  // Capsules move with their bones too.
  const caps = mesh.getCapsules();
  assert.equal(caps.filter((c) => c.name === 'thigh').length, 2);
  assert.ok(caps.every((c) => c.r > 0.03 && Number.isFinite(c.a.x + c.b.y)));
});

test('Wardrobe: every outfit equips on both profiles; garments share the skeleton', () => {
  const mesh = new CharacterMesh({ femininity: 1 });
  const parent = new THREE.Group();
  parent.add(mesh.root);
  const wardrobe = new Wardrobe({ mesh, wind: null, worldParent: parent });
  for (const f of [0, 1]) {
    mesh.setFemininity(f);
    wardrobe.syncProfile();
    const style = f ? 'feminine' : 'masculine';
    for (const outfit of Object.keys(OUTFITS)) {
      wardrobe.equipOutfit(outfit);
      for (const name of OUTFITS[outfit]) {
        const profiles = WARDROBE_ITEMS[name].profiles;
        const expected = !profiles || profiles.includes(style);
        assert.equal(wardrobe.items.has(name), expected, `${style} ${outfit}: ${name}`);
      }
      assert.ok(wardrobe.items.has(f ? 'hairLong' : 'hairShort'), 'hairstyle follows the profile');
      for (const it of wardrobe.items.values()) {
        if (it.spring) continue; // spring tails carry their own bone chain
        for (const m of it.meshes) {
          if (!m.isSkinnedMesh) continue; // cloth meshes are world-space
          // (assert.ok: a failing assert.equal would diff two whole skeletons)
          assert.ok(m.skeleton === mesh.skeleton, `${it.name} is not bound to the body skeleton`);
          assert.ok(m.morphTargetInfluences[0] === f, `${it.name} does not follow the morph`);
        }
      }
      for (let i = 0; i < 10; i++) wardrobe.update(1 / 60, 0);
    }
  }
  // Outfit changes only rebuild the difference (shared items keep their state).
  wardrobe.equipOutfit('explorer');
  const boots = wardrobe.items.get('boots');
  wardrobe.equipOutfit('skirtShirt');
  assert.equal(wardrobe.items.get('boots'), boots);
  // Body regions under the bodice are hidden; changing outfit restores them.
  wardrobe.equipOutfit('silverDress');
  const belly = mesh.body.geometry.groups.find((g) => REGIONS[g.region] === 'belly');
  assert.equal(belly.materialIndex, 1);
  wardrobe.equipOutfit('bikini');
  assert.equal(belly.materialIndex, 0);
});

test('Wardrobe: skirt cloth never penetrates the leg capsules while walking', () => {
  const mesh = new CharacterMesh({ femininity: 1 });
  const parent = new THREE.Group();
  parent.add(mesh.root);
  const wind = {
    direction: new THREE.Vector3(1, 0, 0.3).normalize(),
    strength: 1,
    sample: (_p, out) => out.set(4, 0, 1.2),
  };
  const wardrobe = new Wardrobe({ mesh, wind, worldParent: parent });
  wardrobe.equipOutfit('skirtShirt');
  const skirt = wardrobe.items.get('skirt').cloth;
  const hem = wardrobe.items.get('shirtHem').cloth;
  const B = mesh.bones;
  const dt = 1 / 60;
  const closest = new THREE.Vector3();
  const ab = new THREE.Vector3();
  const pt = new THREE.Vector3();
  let worst = Infinity;
  for (let step = 0; step < 240; step++) {
    // Exaggerated stride + forward travel.
    const ph = step * dt * Math.PI * 2 * 1.4;
    B.thighL.rotation.x = Math.sin(ph) * 0.75;
    B.thighR.rotation.x = -Math.sin(ph) * 0.75;
    B.shinL.rotation.x = Math.max(0, -Math.cos(ph)) * 0.9;
    B.shinR.rotation.x = Math.max(0, Math.cos(ph)) * 0.9;
    mesh.root.position.z += 1.6 * dt;
    wardrobe.update(dt, 0);
    if (step < 30) continue; // let the cloth settle from its initial drape
    for (const cloth of [skirt, hem]) {
      for (const cap of cloth.capsules) {
        if (cap.name !== 'thigh' && cap.name !== 'shin') continue;
        ab.subVectors(cap.b, cap.a);
        for (let i = 0; i < cloth.pos.length; i += 3) {
          pt.fromArray(cloth.pos, i);
          const h = THREE.MathUtils.clamp(pt.clone().sub(cap.a).dot(ab) / ab.lengthSq(), 0, 1);
          closest.copy(cap.a).addScaledVector(ab, h);
          worst = Math.min(worst, pt.distanceTo(closest) - cap.r);
        }
      }
      for (const v of cloth.pos) assert.ok(Number.isFinite(v));
    }
  }
  // Collision runs inside the solver loop with a per-layer margin: the skirt
  // must actually touch the legs (constraint active) yet never go inside.
  assert.ok(worst < skirt.collisionMargin + 0.01, 'skirt never reached the legs — test is not exercising collisions');
  assert.ok(worst > -0.002, `cloth penetrated a leg capsule by ${(-worst * 1000).toFixed(1)} mm`);
  // Outer layer (shirt hem) keeps a larger clearance than the inner skirt.
  assert.ok(hem.collisionMargin > skirt.collisionMargin);
});

test('Wardrobe: skirt stays draped while walking at 4 fps (real controller + animator)', async () => {
  // Long frames must not change the cloth's physics: sub-steps stretch to
  // cover the frame in real time, pins and leg colliders sweep with it.
  const physics = await createPhysics();
  const scene = new THREE.Scene();
  new Sand(physics);
  new CityBuilder(physics, { get: () => null }).build();
  const interactions = new InteractionManager();
  const vehicles = new VehicleSystem({ physics, interactions, parent: scene });
  const wind = new WindSystem();
  const environment = { wind, groundHeightAt: (x, z) => cityGroundHeight(x, z) ?? sandHeight(x, z), setFocus() {} };
  const keys = new Set();
  const input = {
    isDown: (a) => keys.has(a),
    axis: () => 0,
    moveVector: (o) => o.set(0, keys.has('forward') ? 1 : 0),
    consume: () => false,
    flush() {},
    consumeLook: (o) => o.set(0, 0),
    consumeZoom: () => 0,
    lastLookTime: 0,
  };
  const camera = new THREE.PerspectiveCamera();
  camera.position.set(0, 10, 0);
  camera.lookAt(1, 10, 0);
  camera.updateMatrixWorld();
  const noop = {
    setTarget() {},
    snapBehind() {},
    setMode() {},
    setDebugState() {},
    showVehicle() {},
    hideVehicle() {},
    toast() {},
  };
  const ch = new CharacterController({
    physics,
    input,
    interactions,
    vehicles,
    environment,
    cameraRig: noop,
    hud: noop,
    parent: scene,
    camera,
    spawn: WORLD.spawn,
  });
  ch.setProfile(1);
  ch.equipOutfit('skirtShirt');
  const skirt = ch.wardrobe.items.get('skirt').cloth;
  const pelvis = ch.rig.body.bones.pelvis;

  const FRAME = 1 / 4;
  const fixed = 1 / 60;
  let acc = 0;
  const frame = () => {
    acc += FRAME;
    while (acc >= fixed) {
      ch.fixedUpdate(fixed);
      physics.step();
      physics.capture();
      acc -= fixed;
    }
    physics.interpolate(acc / fixed);
    wind.update(FRAME);
    ch.update(FRAME);
    ch.lateUpdate(FRAME);
  };
  for (let i = 0; i < 4; i++) frame();
  keys.add('forward');
  let maxRise = -Infinity;
  const hip = new THREE.Vector3();
  for (let i = 0; i < 16; i++) {
    frame();
    if (i < 4) continue;
    pelvis.getWorldPosition(hip);
    const row = (skirt.rows - 1) * skirt.cols;
    for (let c = 0; c < skirt.cols; c++) maxRise = Math.max(maxRise, skirt.pos[(row + c) * 3 + 1] - hip.y);
    for (const v of skirt.pos) assert.ok(Number.isFinite(v));
  }
  assert.equal(ch.state, 'walk');
  assert.ok(maxRise < -0.15, `skirt hem flew up to ${maxRise.toFixed(2)} m relative to the pelvis`);
});

test('Wardrobe: shirt hem stays layered outside the skirt on both profiles', () => {
  for (const f of [1, 0]) {
    const mesh = new CharacterMesh({ femininity: f });
    const parent = new THREE.Group();
    parent.add(mesh.root);
    const wind = { direction: new THREE.Vector3(0, 0, -1), strength: 1, sample: (_p, out) => out.set(1.5, 0, -5) };
    const wardrobe = new Wardrobe({ mesh, wind, worldParent: parent });
    wardrobe.equipOutfit('skirtShirt');
    const skirt = wardrobe.items.get('skirt').cloth;
    const hem = wardrobe.items.get('shirtHem').cloth;
    assert.equal(hem.innerLayers[0]?.cloth, skirt, 'hem is layered over the skirt');
    assert.ok(
      wardrobe._cloth.indexOf(wardrobe.items.get('skirt')) < wardrobe._cloth.indexOf(wardrobe.items.get('shirtHem')),
    );
    const axis = new THREE.Vector3();
    let worst = Infinity;
    let contacts = 0;
    for (let step = 0; step < 180; step++) {
      const ph = step * (1 / 60) * Math.PI * 2;
      mesh.bones.thighL.rotation.x = Math.sin(ph) * 0.5;
      mesh.bones.thighR.rotation.x = -Math.sin(ph) * 0.5;
      wardrobe.update(1 / 60, 0);
      if (step < 60) continue;
      mesh.bones.pelvis.getWorldPosition(axis);
      const top = 5 * skirt.cols;
      for (let k = hem.cols; k < hem.count; k++) {
        const ox = hem.pos[k * 3] - axis.x;
        const oz = hem.pos[k * 3 + 2] - axis.z;
        const rp = Math.hypot(ox, oz);
        const [ux, uz] = [ox / rp, oz / rp];
        // Skirt surface radius along this hem particle's radial ray.
        let surface = -1;
        for (let q = 0; q < top; q++) {
          if (Math.abs(skirt.pos[q * 3 + 1] - hem.pos[k * 3 + 1]) > 0.03) continue;
          const qx = skirt.pos[q * 3] - axis.x;
          const qz = skirt.pos[q * 3 + 2] - axis.z;
          const along = qx * ux + qz * uz;
          if (Math.abs(qz * ux - qx * uz) < 0.025) surface = Math.max(surface, along);
        }
        if (surface < 0) continue;
        contacts++;
        worst = Math.min(worst, rp - surface);
      }
    }
    assert.ok(contacts > 100, 'hem and skirt actually overlap in height');
    assert.ok(worst > 0.004, `f=${f}: hem dipped ${(-worst * 1000).toFixed(1)} mm inside the skirt`);
  }
});

test('ParticlePool: swap-remove keeps the live set packed and intact', () => {
  const pool = new ParticlePool(64);
  const rnd = lcg(7);
  const live = new Set();
  let id = 0;
  for (let n = 0; n < 2000; n++) {
    if (rnd() < 0.55) {
      const i = pool.spawn();
      if (live.size === 64) {
        assert.equal(i, -1, 'spawn must fail when the pool is full');
        continue;
      }
      assert.equal(i, live.size);
      pool.seed[i] = ++id;
      pool.pos[i * 3 + 1] = id * 2;
      live.add(id);
    } else if (pool.count > 0) {
      const i = Math.floor(rnd() * pool.count);
      live.delete(pool.seed[i]);
      pool.kill(i);
    }
    assert.equal(pool.count, live.size);
  }
  for (let i = 0; i < pool.count; i++) {
    assert.ok(live.has(pool.seed[i]));
    assert.equal(pool.pos[i * 3 + 1], pool.seed[i] * 2, 'particle data moved without its id');
  }
});

test('ParticleSystem: wind-driven update, expiry and kill test', () => {
  const wind = { direction: new THREE.Vector3(1, 0, 0), speed: 6, strength: 1 };
  const ps = new ParticleSystem({ wind, capacity: 32 });
  for (let i = 0; i < 40; i++) ps.emit(PARTICLE_TYPES.dust, 0, 2, 0, 0, 0, 0, i < 10 ? 0.2 : 5, 0.05);
  assert.equal(ps.pool.count, 32, 'emissions beyond capacity are dropped, not allocated');
  for (let i = 0; i < 30; i++) ps.update(1 / 60);
  assert.equal(ps.pool.count, 22, 'short-lived particles expire');
  assert.equal(ps.mesh.count, 22);
  let meanX = 0;
  for (let i = 0; i < ps.pool.count; i++) meanX += ps.pool.pos[i * 3] / ps.pool.count;
  assert.ok(meanX > 0.5, 'dust drifts downwind');
  ps.killTest = (_type, x) => x > 1.0;
  for (let i = 0; i < 120; i++) ps.update(1 / 60);
  for (let i = 0; i < ps.pool.count; i++) assert.ok(ps.pool.pos[i * 3] <= 1.0 + 1e-6);
});

test('Jusant grade: cool shadows, warm highlights, monotonic greys', () => {
  const [r0, , b0] = gradeColor(0.15, 0.15, 0.15);
  const [r1, , b1] = gradeColor(0.85, 0.85, 0.85);
  assert.ok(b0 > r0, 'shadows lean cool');
  assert.ok(r1 > b1, 'highlights lean warm');
  let prev = -1;
  for (let x = 0; x <= 1.0001; x += 0.05) {
    const [r, g, b] = gradeColor(x, x, x);
    const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    assert.ok(l >= prev - 1e-6, 'grade must not invert tones');
    prev = l;
  }
  const black = gradeColor(0, 0, 0);
  assert.ok(Math.max(...black) < 0.08 && black[2] > black[0], 'blacks slightly lifted, towards blue');
  const lut = createJusantLUT(8);
  assert.equal(lut.image.data.length, 8 * 8 * 8 * 4);
});

test('BONES and REGIONS are stable public contracts', () => {
  assert.equal(BONES[0], 'pelvis');
  assert.ok(REGIONS.includes('hand') && REGIONS.includes('foot'));
});

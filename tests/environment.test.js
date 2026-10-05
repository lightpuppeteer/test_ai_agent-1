import { test } from 'node:test';
import assert from 'node:assert/strict';
import { THREE, createPhysics, lcg } from './helpers.js';
import { Sand } from '../src/environment/Sand.js';
import { sandHeight } from '../src/environment/Terrain.js';
import { GerstnerWaves } from '../src/environment/GerstnerWaves.js';
import { BuoyancySystem } from '../src/environment/Buoyancy.js';
import { GROUPS } from '../src/config.js';

test('sand heightfield collider matches the analytic (shader) dune surface', async () => {
  const physics = await createPhysics();
  new Sand(physics);
  physics.world.step();
  const rand = lcg(1);
  let maxErr = 0;
  for (let i = 0; i < 400; i++) {
    const x = -110 + rand() * 220;
    const z = -39 + rand() * 155;
    const hit = physics.raycast({ x, y: 50, z }, { x: 0, y: -1, z: 0 }, 100, GROUPS.QUERY_CAMERA);
    assert.ok(hit, `ray missed the sand at ${x}, ${z}`);
    maxErr = Math.max(maxErr, Math.abs(hit.point.y - sandHeight(x, z)));
  }
  assert.ok(maxErr < 0.05, `max error ${maxErr.toFixed(4)} m`);
});

test('Gerstner CPU sampler inverts horizontal displacement', () => {
  const waves = new GerstnerWaves();
  const rand = lcg(7);
  const d = new THREE.Vector3();
  let maxRes = 0;
  for (let i = 0; i < 300; i++) {
    const x = -60 + rand() * 120;
    const z = 30 + rand() * 80;
    const t = rand() * 100;
    let px = x;
    let pz = z;
    for (let k = 0; k < 4; k++) {
      waves.displacement(px, pz, t, d);
      px = x - d.x;
      pz = z - d.z;
    }
    waves.displacement(px, pz, t, d);
    maxRes = Math.max(maxRes, Math.hypot(px + d.x - x, pz + d.z - z));
  }
  assert.ok(maxRes < 0.01, `residual ${maxRes.toFixed(5)} m`);
});

test('a crate floats at its Archimedes draft and stays stable', async () => {
  const physics = await createPhysics();
  const R = physics.RAPIER;
  new Sand(physics);
  const waves = new GerstnerWaves();
  const buoyancy = new BuoyancySystem(physics, waves);
  const body = physics.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(0, 1.5, 70));
  physics.createCollider(R.ColliderDesc.cuboid(0.4, 0.4, 0.4).setDensity(420).setCollisionGroups(GROUPS.DYNAMIC), body);
  buoyancy.add(body, {
    ...BuoyancySystem.boxSamples(new THREE.Vector3(0.8, 0.8, 0.8)),
    linearDrag: 70,
    angularDrag: 1.2,
  });
  const dt = 1 / 60;
  const subs = [];
  let maxV = 0;
  for (let s = 0; s < 60 * 30; s++) {
    buoyancy.fixedUpdate(dt, s * dt);
    physics.world.step();
    if (s > 600) {
      subs.push(buoyancy.bodies[0].submerged);
      const v = body.linvel();
      maxV = Math.max(maxV, Math.hypot(v.x, v.y, v.z));
    }
  }
  const avg = subs.reduce((a, b) => a + b, 0) / subs.length;
  assert.ok(
    Math.abs(avg - 420 / 1025) < 0.08,
    `average submersion ${avg.toFixed(3)}, expected ≈ ${(420 / 1025).toFixed(3)}`,
  );
  assert.ok(maxV < 6, `unstable: |v| reached ${maxV.toFixed(2)} m/s`);
});

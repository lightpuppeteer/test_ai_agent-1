import { test } from 'node:test';
import assert from 'node:assert/strict';
import { THREE, createPhysics, upOf } from './helpers.js';
import { Sand } from '../src/environment/Sand.js';
import { VehicleSystem } from '../src/vehicle/VehicleSystem.js';
import { Drivetrain } from '../src/vehicle/Drivetrain.js';
import { InteractionManager } from '../src/interaction/InteractionManager.js';
import { SURFACE } from '../src/config.js';

test('torque curve interpolation is smooth and bounded by its samples', () => {
  const d = new Drivetrain();
  let prev = d.torqueAt(800);
  for (let rpm = 800; rpm <= 6500; rpm += 25) {
    const t = d.torqueAt(rpm);
    assert.ok(t >= 94 && t <= 187, `torque ${t} at ${rpm}`);
    assert.ok(Math.abs(t - prev) < 3, `discontinuity at ${rpm} rpm`);
    prev = t;
  }
});

test('raycast car: settle, launch, gearbox, brakes, reverse, steering, surfaces', async (t) => {
  const physics = await createPhysics();
  const road = physics.createStaticGroup('road', { surface: SURFACE.STONE });
  road.addBox(new THREE.Vector3(0, 2, -300), new THREE.Vector3(2000, 2, 500));
  new Sand(physics);
  const sys = new VehicleSystem({ physics, interactions: new InteractionManager(), parent: null });
  const car = sys.spawnCar(new THREE.Vector3(-800, 3.75, -300), Math.PI / 2);
  const keys = new Set();
  const input = { isDown: (a) => keys.has(a), axis: (n, p) => (keys.has(p) ? 1 : 0) - (keys.has(n) ? 1 : 0) };
  const dt = 1 / 60;
  const step = (n) => {
    for (let i = 0; i < n; i++) {
      sys.fixedUpdate(dt);
      physics.world.step();
    }
  };

  await t.test('settles on its suspension and the parking brake holds', () => {
    step(240);
    const a = { ...car.body.translation() };
    step(120);
    const b = car.body.translation();
    assert.ok(Math.hypot(b.x - a.x, b.z - a.z) < 0.01, 'car creeps while parked');
    assert.ok(b.y > 3.3 && b.y < 3.9, `ride height ${b.y}`);
  });

  sys.setDriver(car, input);
  await t.test('0-100 km/h in a plausible time with automatic up-shifts', () => {
    keys.add('forward');
    let t100 = null;
    let maxGear = 1;
    for (let i = 0; i < 60 * 25; i++) {
      step(1);
      if (t100 === null && car.speed * 3.6 >= 100) t100 = (i + 1) * dt;
      maxGear = Math.max(maxGear, car.drivetrain.gear);
    }
    assert.ok(t100 !== null && t100 > 7 && t100 < 16, `0-100 in ${t100}s`);
    assert.ok(maxGear >= 4, `max gear ${maxGear}`);
    assert.ok(upOf(car.body.rotation()).y > 0.97, 'car not level at speed');
  });

  await t.test('brakes decelerate at 0.55–1.05 g', () => {
    keys.delete('forward');
    keys.add('backward');
    const v0 = car.speed;
    let tb = 0;
    while (car.speed > 5 && tb < 20) {
      step(1);
      tb += dt;
    }
    const decel = (v0 - car.speed) / tb;
    assert.ok(decel > 5.5 && decel < 10.5, `${decel.toFixed(2)} m/s²`);
  });

  await t.test('holding brake at standstill engages a speed-limited reverse', () => {
    step(180);
    assert.equal(car.drivetrain.gear, -1);
    assert.ok(car.speed < -0.5 && car.speed > -7, `reverse speed ${car.speed}`);
    keys.delete('backward');
    step(120);
  });

  await t.test('positive steering turns left without rolling over', () => {
    keys.add('forward');
    while (car.speed < 11) step(1);
    keys.delete('forward');
    keys.add('left');
    let minUp = 1;
    for (let i = 0; i < 180; i++) {
      step(1);
      minUp = Math.min(minUp, upOf(car.body.rotation()).y);
    }
    keys.delete('left');
    assert.ok(car.body.angvel().y > 0.1, `yaw rate ${car.body.angvel().y}`);
    assert.ok(minUp > 0.95, `body roll too large (up.y ${minUp})`);
  });

  await t.test('wheels read the surface material under them (sand)', () => {
    car.body.setTranslation({ x: 0, y: 4, z: 0 }, true);
    car.body.setLinvel({ x: 0, y: 0, z: 0 }, true);
    car.body.setAngvel({ x: 0, y: 0, z: 0 }, true);
    car.body.setRotation({ x: 0, y: 0, z: 0, w: 1 }, true);
    step(120);
    assert.deepEqual(car.wheelSurfaces, ['sand', 'sand', 'sand', 'sand']);
  });
});

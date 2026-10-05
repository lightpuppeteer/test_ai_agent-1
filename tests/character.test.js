import { test } from 'node:test';
import assert from 'node:assert/strict';
import { THREE, createPhysics } from './helpers.js';
import { Sand } from '../src/environment/Sand.js';
import { sandHeight, sandNormal } from '../src/environment/Terrain.js';
import { CityBuilder, cityGroundHeight, plazaHeight } from '../src/environment/CityBuilder.js';
import { WindSystem } from '../src/environment/WindSystem.js';
import { alignToNormal } from '../src/environment/BeachProps.js';
import { InteractionManager } from '../src/interaction/InteractionManager.js';
import { Interactable, Anchor, INTERACTION_TYPE, staticRoot } from '../src/interaction/Interactable.js';
import { VehicleSystem } from '../src/vehicle/VehicleSystem.js';
import { CharacterController } from '../src/character/CharacterController.js';
import { WORLD } from '../src/config.js';

/**
 * Headless end-to-end run of the character FSM against the real city and
 * beach colliders (no renderer): locomotion, slopes, walls, jump, sit,
 * lie down, enter/drive/exit vehicle.
 */
test('character FSM end-to-end', async (t) => {
  const physics = await createPhysics();
  const scene = new THREE.Scene();
  new Sand(physics);
  const city = new CityBuilder(physics, { get: () => null }).build(); // textures not needed headless
  scene.add(city.group);
  const interactions = new InteractionManager();
  city.interactables.forEach((i) => interactions.register(i));

  // One towel, built like BeachProps.towel (minus the textured mesh).
  {
    const [x, z, yaw] = [-8, 6, 0.15];
    const root = staticRoot(new THREE.Vector3(x, sandHeight(x, z), z), yaw);
    const n = sandNormal(x, z, new THREE.Vector3());
    const localQ = root.quaternion.clone().invert().multiply(alignToNormal(n, yaw));
    interactions.register(
      new Interactable({
        type: INTERACTION_TYPE.TOWEL,
        label: 'Lie down',
        object: root,
        anchors: [
          new Anchor({
            id: 'towel',
            position: new THREE.Vector3(0, 0.03, 0),
            quaternion: localQ,
            meta: { standOffset: new THREE.Vector3(0.95, 0, 0.2) },
          }),
        ],
        radius: 1.7,
        center: new THREE.Vector3(0, 0.2, 0),
      }),
    );
  }
  const vehicles = new VehicleSystem({ physics, interactions, parent: scene });
  const car = vehicles.spawnCar(new THREE.Vector3(-8, 3.75, -48.6), Math.PI / 2);

  const wind = new WindSystem();
  const environment = { wind, groundHeightAt: (x, z) => cityGroundHeight(x, z) ?? sandHeight(x, z), setFocus() {} };
  const keys = new Set();
  const pressed = new Set();
  const input = {
    isDown: (a) => keys.has(a),
    axis: (n, p) => (keys.has(p) ? 1 : 0) - (keys.has(n) ? 1 : 0),
    moveVector: (out) =>
      out.set(
        (keys.has('right') ? 1 : 0) - (keys.has('left') ? 1 : 0),
        (keys.has('forward') ? 1 : 0) - (keys.has('backward') ? 1 : 0),
      ),
    consume: (a) => pressed.delete(a),
    flush: (...a) => a.forEach((x) => pressed.delete(x)),
    consumeLook: (o) => o.set(0, 0),
    consumeZoom: () => 0,
    lastLookTime: 0,
  };
  const camera = new THREE.PerspectiveCamera();
  const lookAlong = (x, z) => {
    camera.position.set(0, 10, 0);
    camera.lookAt(x, 10, z);
    camera.updateMatrixWorld();
  };
  lookAlong(0, 1);
  const cameraRig = { setTarget() {}, snapBehind() {}, setMode() {} };
  const hud = { setDebugState() {}, showVehicle() {}, hideVehicle() {}, toast() {} };
  const ch = new CharacterController({
    physics,
    input,
    interactions,
    vehicles,
    environment,
    cameraRig,
    hud,
    parent: scene,
    camera,
    spawn: WORLD.spawn,
  });

  const dt = 1 / 60;
  const frame = () => {
    ch.fixedUpdate(dt);
    vehicles.fixedUpdate(dt);
    physics.step();
    physics.capture();
    physics.interpolate(1);
    wind.update(dt);
    ch.update(dt);
    vehicles.update(dt);
    ch.lateUpdate(dt);
  };
  const run = (sec) => {
    for (let i = 0; i < Math.round(sec * 60); i++) frame();
  };
  const runUntil = (pred, maxSec = 10) => {
    for (let i = 0; i < maxSec * 60 && !pred(); i++) frame();
  };
  const feet = () => ch.body.getFeet(new THREE.Vector3());
  const teleport = (x, z, yaw = 0) => {
    ch.body.teleportFeet(new THREE.Vector3(x, environment.groundHeightAt(x, z) + 0.05, z));
    ch.yaw = yaw;
    run(0.3);
  };

  await t.test('spawns grounded and idle on the promenade', () => {
    run(1);
    assert.equal(ch.state, 'idle');
    assert.ok(ch.body.grounded);
    assert.ok(Math.abs(feet().y - WORLD.promenade.height) < 0.06);
  });

  await t.test('idle → walk → run → idle, down onto the sand', () => {
    keys.add('forward');
    run(0.5);
    assert.equal(ch.state, 'walk');
    keys.add('run');
    run(0.5);
    assert.equal(ch.state, 'run');
    run(4);
    keys.clear();
    run(0.6);
    assert.equal(ch.state, 'idle');
    const f = feet();
    assert.ok(f.z > -30 && ch.body.grounded, `feet ${f.toArray()}`);
    assert.ok(Math.abs(f.y - sandHeight(f.x, f.z)) < 0.12);
  });

  await t.test('jump → airborne → lands', () => {
    pressed.add('jump');
    run(0.2);
    assert.equal(ch.state, 'airborne');
    run(1.2);
    assert.equal(ch.state, 'idle');
  });

  await t.test('climbs the slanted plaza', () => {
    lookAlong(0, -1);
    teleport(-2, -54, Math.PI);
    keys.add('forward');
    run(8);
    keys.clear();
    run(0.3);
    const f = feet();
    assert.ok(f.z < -64 && Math.abs(f.y - plazaHeight(f.x, f.z)) < 0.1, `feet ${f.toArray()}`);
  });

  await t.test('is stopped by house walls and passes through the arcade', () => {
    lookAlong(-1, 0);
    teleport(-19, -66, -Math.PI / 2);
    keys.add('forward');
    run(4);
    keys.clear();
    assert.ok(feet().x > -24 && feet().x < -23.3, `x ${feet().x}`);
    lookAlong(1, 0);
    teleport(-15, -102, Math.PI / 2);
    keys.add('forward');
    run(9);
    keys.clear();
    assert.ok(feet().x > -2 && ch.body.grounded, `x ${feet().x}`);
  });

  await t.test('sits on a bench approached from behind, then stands up', () => {
    lookAlong(0, 1);
    teleport(-12.3, -43.5, 0);
    run(0.2);
    assert.equal(interactions.focus?.type, INTERACTION_TYPE.SEAT);
    pressed.add('interact');
    runUntil(() => ch.fsm.current.phase === 'seated', 8);
    assert.equal(ch.state, 'sit');
    assert.equal(ch.body.posture, 'seated');
    pressed.add('interact');
    runUntil(() => ch.state === 'idle', 4);
    assert.equal(ch.body.posture, 'standing');
    const f = feet();
    assert.ok(physics.isCapsuleFree({ x: f.x, y: f.y + 0.92, z: f.z }, 0.55, 0.3, undefined, ch.body.body));
  });

  await t.test('lies down on a towel with a horizontal capsule, then gets up', () => {
    teleport(-7.0, 6.4, -Math.PI / 2);
    run(0.2);
    assert.equal(interactions.focus?.type, INTERACTION_TYPE.TOWEL);
    pressed.add('interact');
    runUntil(() => ch.fsm.current.phase === 'lying', 8);
    assert.equal(ch.state, 'layDown');
    const r = ch.body.body.rotation();
    const axis = new THREE.Vector3(0, 1, 0).applyQuaternion(new THREE.Quaternion(r.x, r.y, r.z, r.w));
    assert.ok(Math.abs(axis.y) < 0.15, `capsule axis ${axis.toArray()}`);
    pressed.add('interact');
    runUntil(() => ch.state === 'idle', 5);
    assert.equal(ch.state, 'idle');
  });

  await t.test('enters, drives and safely exits the car', () => {
    const cp = car.body.translation();
    lookAlong(1, 0);
    teleport(cp.x + 0.3, cp.z - 2.2, 0);
    run(0.2);
    assert.equal(interactions.focus?.type, INTERACTION_TYPE.VEHICLE);
    pressed.add('interact');
    runUntil(() => ch.state === 'drive', 8);
    assert.equal(ch.state, 'drive');
    assert.equal(ch.rig.root.parent, car.model.seatMount);
    assert.equal(ch.body.body.isEnabled(), false);

    const c0 = { ...car.body.translation() };
    keys.add('forward');
    run(2.5);
    keys.delete('forward');
    const c1 = car.body.translation();
    assert.ok(Math.hypot(c1.x - c0.x, c1.z - c0.z) > 5, 'car did not move');
    pressed.add('interact');
    run(0.1);
    assert.equal(ch.state, 'drive', 'must not exit at speed');

    keys.add('backward');
    runUntil(() => car.speed < 0.5, 10);
    keys.delete('backward');
    run(0.5);
    pressed.add('interact');
    runUntil(() => ch.state === 'idle', 6);
    assert.equal(ch.state, 'idle');
    assert.equal(ch.body.body.isEnabled(), true);
    assert.equal(ch.rig.root.parent, scene);
    const f = feet();
    const p = car.body.translation();
    assert.ok(Math.hypot(f.x - p.x, f.z - p.z) < 3.5);
  });

  await t.test('secondary motion (cloth) stays finite', () => {
    for (const v of ch.wardrobe.items.get('cloak').cloth.pos) assert.ok(Number.isFinite(v));
  });
});

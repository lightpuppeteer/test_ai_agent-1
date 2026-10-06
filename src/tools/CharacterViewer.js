import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { CHARACTER, WORLD, RENDER } from '../config.js';
import { sharedUniforms } from '../shaders/common.glsl.js';
import { SkyIBL } from '../lighting/IBL.js';
import { CharacterRig } from '../character/CharacterRig.js';
import { Wardrobe } from '../character/Wardrobe.js';
import { loadCharacterAsset } from '../character/CharacterAsset.js';
import { WindSystem } from '../environment/WindSystem.js';

/**
 * Character viewer (dev tool): the game's character stack — CharacterRig
 * animator, Wardrobe (cloth, springs, authored garments) and stylised
 * materials under the game's sky IBL — without the world or physics.
 *
 *   npm run dev → http://localhost:5173/viewer.html
 *   ?procedural  use the procedural body instead of the authored glTF
 *   ?capture     render on demand only (for scripted screenshots)
 *
 * Keys: 1–8 poses (idle, walk, run, jump, sit, kneel, lie, drive), O outfit,
 * T turntable. `window.__viewer` exposes the scene for scripted captures.
 */
const params = new URLSearchParams(location.search);
const container = document.getElementById('app');
const status = document.getElementById('status');

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping;
renderer.toneMappingExposure = RENDER.exposure;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
container.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(32, innerWidth / innerHeight, 0.05, 200);
camera.position.set(1.6, 1.35, 3.2);
const controls = new OrbitControls(camera, renderer.domElement);
controls.target.set(0, 0.95, 0);
controls.enableDamping = true;

// Lighting: the game's warm late-afternoon sun + procedural sky IBL.
const az = THREE.MathUtils.degToRad(WORLD.sun.azimuthDeg + 140);
const el = THREE.MathUtils.degToRad(WORLD.sun.elevationDeg + 10);
const sunDir = new THREE.Vector3(Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el));
sharedUniforms.uSunDir.value.copy(sunDir);
const sun = new THREE.DirectionalLight(sharedUniforms.uSunColor.value, 3.2);
sun.position.copy(sunDir).multiplyScalar(8);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -2, right: 2, top: 2.5, bottom: -0.5, near: 0.5, far: 20 });
sun.shadow.bias = -0.0003;
sun.shadow.normalBias = 0.02;
scene.add(sun);
const ibl = new SkyIBL(renderer, { exposure: RENDER.ibl.exposure, groundBounce: RENDER.ibl.groundBounce });
scene.environment = ibl.update();
scene.environmentIntensity = RENDER.ibl.intensity;
scene.background = new THREE.Color(0x3a3631);

const ground = new THREE.Mesh(
  new THREE.CircleGeometry(4, 64).rotateX(-Math.PI / 2),
  new THREE.MeshStandardMaterial({ color: 0x8b8073, roughness: 0.95 }),
);
ground.receiveShadow = true;
scene.add(ground);
const seat = new THREE.Mesh(
  new THREE.BoxGeometry(1.2, 0.45, 0.42).translate(0, 0.225, -0.06),
  new THREE.MeshStandardMaterial({ color: 0x9a9184, roughness: 0.9 }),
);
seat.castShadow = seat.receiveShadow = true;
seat.visible = false;
scene.add(seat);

const wind = new WindSystem();
const asset = params.has('procedural') ? null : await loadCharacterAsset(CHARACTER.asset);
const rig = new CharacterRig({ femininity: CHARACTER.femininity, asset });
scene.add(rig.root);
rig.update(0);
const wardrobe = new Wardrobe({ mesh: rig.body, wind, worldParent: scene });
wardrobe.equipOutfit(wardrobe.outfitNames.includes(CHARACTER.outfit) ? CHARACTER.outfit : wardrobe.outfitNames[0]);
rig.root.traverse((o) => {
  if (o.isMesh && o.name !== 'Eyelashes' && o.name !== 'Eyebrows') o.castShadow = true;
});

// --- Poses -------------------------------------------------------------------
const POSES = {
  idle: () => ({ speed: 0 }),
  walk: () => ({ speed: 1.7 }),
  run: () => ({ speed: 5.4 }),
  jump: () => ({ speed: 2, grounded: false, vy: 2 }),
  sit: () => ({ pose: 'sit', params: { seatHeight: 0.45 }, seat: true }),
  kneel: () => ({ pose: 'kneel' }),
  lie: () => ({ pose: 'lay' }),
  drive: () => ({ pose: 'drive', params: { seatHeight: 0.3 } }),
};
let current = 'idle';
let turntable = false;
function setPose(name) {
  current = name;
  const p = POSES[name]();
  rig.playPose(p.pose ?? null, 0.35, p.params ?? {});
  seat.visible = !!p.seat;
  refreshUI();
}

// --- UI ----------------------------------------------------------------------
const ui = document.getElementById('ui');
function button(label, onClick, on = () => false) {
  const b = document.createElement('button');
  b.textContent = label;
  b.onclick = onClick;
  b._on = on;
  ui.appendChild(b);
  return b;
}
Object.keys(POSES).forEach((n, i) => button(`${i + 1} ${n}`, () => setPose(n), () => current === n));
button('O outfit', () => {
  const names = wardrobe.outfitNames;
  wardrobe.equipOutfit(names[(names.indexOf(wardrobe.outfit) + 1) % names.length]);
  refreshUI();
});
button('T turntable', () => ((turntable = !turntable), refreshUI()), () => turntable);
function refreshUI() {
  for (const b of ui.children) b.classList.toggle('on', b._on());
  status.textContent = `${asset ? 'Authored character' : 'Procedural character'} · outfit: ${wardrobe.outfit} · pose: ${current}`;
}
addEventListener('keydown', (e) => {
  const i = Number(e.key) - 1;
  if (i >= 0 && i < 8) setPose(Object.keys(POSES)[i]);
  if (e.code === 'KeyO') ui.querySelector('button:nth-last-child(2)').click();
  if (e.code === 'KeyT') (turntable = !turntable), refreshUI();
});
addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});
setPose('idle');

// --- Loop ----------------------------------------------------------------------
const clock = new THREE.Timer();
let time = 0;
function step(dt) {
  time += dt;
  sharedUniforms.uTime.value = time;
  wind.update?.(dt);
  const p = POSES[current]();
  rig.setLocomotion({ speed: p.speed ?? 0, grounded: p.grounded ?? true, turnRate: 0, accel: 0, vy: p.vy ?? 0 });
  if (turntable) rig.root.rotation.y += dt * 0.5;
  rig.update(dt);
  rig.root.updateMatrixWorld(true);
  wardrobe.update(dt, 0);
}
function render() {
  controls.update();
  renderer.render(scene, camera);
}
function frame() {
  clock.update();
  step(Math.min(clock.getDelta(), 1 / 20));
  render();
  requestAnimationFrame(frame);
}
// ?capture: no animation loop — scripted captures call step()/render() themselves.
if (params.has('capture')) render();
else frame();

window.__viewer = { scene, camera, controls, renderer, rig, wardrobe, setPose, step, render, asset };

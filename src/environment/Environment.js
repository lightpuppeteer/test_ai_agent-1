import * as THREE from 'three';
import { PALETTE, RENDER, WORLD } from '../config.js';
import { sharedUniforms } from '../shaders/common.glsl.js';
import { TextureFactory } from './TextureFactory.js';
import { Sky } from './Sky.js';
import { WindSystem } from './WindSystem.js';
import { WindParticles } from './WindParticles.js';
import { Sand } from './Sand.js';
import { GerstnerWaves } from './GerstnerWaves.js';
import { Ocean } from './Ocean.js';
import { BuoyancySystem } from './Buoyancy.js';
import { CityBuilder, cityGroundHeight } from './CityBuilder.js';
import { BeachProps } from './BeachProps.js';
import { sandHeight } from './Terrain.js';

const _v = new THREE.Vector3();
const _rot = new THREE.Matrix4();
const _rotInv = new THREE.Matrix4();

/**
 * Environment — owns everything "world": lighting & atmosphere, sky, global
 * wind (+ particles), beach sand, Gerstner ocean + buoyancy, the Guimarães
 * old-town square and beach props. Registered as an Engine system.
 */
export class Environment {
  /**
   * @param {object} deps
   * @param {import('../core/Engine.js').Engine} deps.engine
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} deps.physics
   * @param {THREE.Object3D} deps.root parent for all environment objects
   */
  constructor({ engine, physics, root }) {
    this.engine = engine;
    this.physics = physics;
    this.root = root;
    this.focus = new THREE.Vector3(WORLD.spawn.x, WORLD.promenade.height, WORLD.spawn.z);
    this.interactables = [];
  }

  build() {
    const { engine, physics, root } = this;
    this.textures = new TextureFactory(engine.renderer);

    this._createLighting();

    this.sky = new Sky();
    root.add(this.sky.mesh);

    this.wind = new WindSystem();
    this.particles = new WindParticles();
    root.add(this.particles.group);

    this.sand = new Sand(physics);
    root.add(this.sand.mesh);

    this.waves = new GerstnerWaves();
    this.ocean = new Ocean(this.waves);
    root.add(this.ocean.mesh);
    this.buoyancy = new BuoyancySystem(physics, this.waves);

    this.city = new CityBuilder(physics, this.textures).build();
    root.add(this.city.group);

    this.props = new BeachProps({ physics, textures: this.textures, buoyancy: this.buoyancy, parent: root }).build();

    this.interactables.push(...this.city.interactables, ...this.props.interactables);
    return this;
  }

  _createLighting() {
    const { scene } = this.engine;
    const { azimuthDeg, elevationDeg } = WORLD.sun;
    const az = THREE.MathUtils.degToRad(azimuthDeg);
    const el = THREE.MathUtils.degToRad(elevationDeg);
    this.sunDir = new THREE.Vector3(Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el)).normalize();
    sharedUniforms.uSunDir.value.copy(this.sunDir);

    // Warm key light; soft PCF shadows that follow the player (texel-snapped).
    this.sun = new THREE.DirectionalLight(PALETTE.sun, 3.1);
    this.sun.castShadow = true;
    const s = this.sun.shadow;
    s.mapSize.set(RENDER.shadowMapSize, RENDER.shadowMapSize);
    s.camera.left = s.camera.bottom = -RENDER.shadowFrustum;
    s.camera.right = s.camera.top = RENDER.shadowFrustum;
    s.camera.near = 1;
    s.camera.far = 220;
    s.bias = -0.0004;
    s.normalBias = 0.035;
    s.radius = 2.5;
    this.root.add(this.sun, this.sun.target);

    // Rich sky-glow ambient: cool blue from above, warm sand bounce from below.
    this.hemi = new THREE.HemisphereLight(PALETTE.hemiSky, PALETTE.hemiGround, 1.6);
    this.root.add(this.hemi);

    // Exponential fog in exactly the sky's horizon colour → seamless blend.
    scene.fog = new THREE.FogExp2(sharedUniforms.uSkyHorizon.value.clone(), RENDER.fogDensity);
    scene.background = sharedUniforms.uSkyHorizon.value.clone();
  }

  /** The point effects (shadows, particles) should centre on — usually the player. */
  setFocus(p) {
    this.focus.copy(p);
  }

  /** Walkable ground height at (x,z): city surfaces first, then sand. */
  groundHeightAt(x, z) {
    return cityGroundHeight(x, z) ?? sandHeight(x, z);
  }

  // ---------------------------------------------------------------------------
  // Engine hooks
  // ---------------------------------------------------------------------------
  fixedUpdate(dt, simTime) {
    this.buoyancy.fixedUpdate(dt, simTime);
  }

  update(dt, renderTime) {
    sharedUniforms.uTime.value = renderTime;
    this.wind.update(dt);
    this._updateShadowCamera();
    const h = this.engine.renderer.getDrawingBufferSize(_v).y;
    this.particles.update(this.focus, h);
  }

  lateUpdate() {
    this.sky.update(this.engine.camera);
  }

  /**
   * Centres the orthographic shadow frustum on the focus point and snaps it
   * to whole shadow-map texels in light space, which removes the shimmering
   * ("swimming") of shadow edges as the player moves.
   */
  _updateShadowCamera() {
    const texel = (2 * RENDER.shadowFrustum) / RENDER.shadowMapSize;
    _rot.lookAt(new THREE.Vector3(), this.sunDir.clone().negate(), new THREE.Vector3(0, 1, 0));
    _rotInv.copy(_rot).invert();
    _v.copy(this.focus).applyMatrix4(_rotInv);
    _v.x = Math.round(_v.x / texel) * texel;
    _v.y = Math.round(_v.y / texel) * texel;
    _v.applyMatrix4(_rot);
    this.sun.target.position.copy(_v);
    this.sun.position.copy(_v).addScaledVector(this.sunDir, 110);
    this.sun.target.updateMatrixWorld();
  }
}

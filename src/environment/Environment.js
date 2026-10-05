import * as THREE from 'three';
import { PALETTE, RENDER, WORLD } from '../config.js';
import { sharedUniforms } from '../shaders/common.glsl.js';
import { heightFogUniforms } from '../lighting/ShaderPatches.js';
import { SkyIBL } from '../lighting/IBL.js';
import { TextureFactory } from './TextureFactory.js';
import { Sky } from './Sky.js';
import { WindSystem } from './WindSystem.js';
import { WindParticles } from './WindParticles.js';
import { Sand } from './Sand.js';
import { GerstnerWaves } from './GerstnerWaves.js';
import { Ocean } from './Ocean.js';
import { BuoyancySystem } from './Buoyancy.js';
import { CityBuilder, cityGroundHeight } from './CityBuilder.js';
import { CityDressing } from './CityDressing.js';
import { BeachProps } from './BeachProps.js';
import { BeachDressing } from './BeachDressing.js';
import { AtmosphereVFX } from '../vfx/AtmosphereVFX.js';
import { sandHeight } from './Terrain.js';

const _v = new THREE.Vector3();
const _rot = new THREE.Matrix4();
const _rotInv = new THREE.Matrix4();
const ORIGIN = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);

/**
 * Environment — owns everything "world". Registered as an Engine system.
 *
 *   lighting     warm sun with 4096² contact-hardening soft shadows (follows
 *                the focus, texel-snapped) + procedural sky IBL (PMREM)
 *                instead of ambient/hemisphere lights; baked vertex AO on
 *                walkable ground
 *   atmosphere   gradient sky, FogExp2 horizon + height fog, global wind,
 *                curling wind streaks, pooled instanced dust/pollen/spray
 *   terrain      dune sand (multi-state dampness), Gerstner ocean + buoyancy
 *   old town     Guimarães-style square + dressing (ivy, rubble, banners,
 *                crates, planters)
 *   beach        towels, parasols, floating props, pebbles, driftwood
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

    this._createSun();
    this._createAtmosphere();

    this.sky = new Sky();
    root.add(this.sky.mesh);

    this.wind = new WindSystem();
    this.particles = new WindParticles({ motes: false });
    root.add(this.particles.group);

    this.waves = new GerstnerWaves();
    this.sand = new Sand(physics, this.waves);
    root.add(this.sand.mesh);
    this.ocean = new Ocean(this.waves);
    root.add(this.ocean.mesh);
    this.buoyancy = new BuoyancySystem(physics, this.waves);

    this._buildOldTown();
    this._buildBeach();

    this.vfx = new AtmosphereVFX({
      wind: this.wind,
      waves: this.waves,
      groundHeightAt: (x, z) => this.groundHeightAt(x, z),
      isCity: (x, z) => z < WORLD.promenade.zLand + 2 && cityGroundHeight(x, z) !== null,
    });
    root.add(this.vfx.mesh);

    this._createIBL();
    return this;
  }

  _buildOldTown() {
    const { physics, root } = this;
    this.city = new CityBuilder(physics, this.textures).build();
    root.add(this.city.group);
    this.cityDressing = new CityDressing({ city: this.city, textures: this.textures, wind: this.wind }).build();
    root.add(this.cityDressing.group);
    // Bake AO last so it sees every collider (houses, benches, crates, planters…).
    this.city.bakeGroundAO();
    this.interactables.push(...this.city.interactables);
  }

  _buildBeach() {
    const { physics, root } = this;
    this.props = new BeachProps({ physics, textures: this.textures, buoyancy: this.buoyancy, parent: root }).build();
    const avoid = this.props.interactables.map((it) => ({ x: it.object.position.x, z: it.object.position.z, r: 1.6 }));
    this.beachDressing = new BeachDressing({ physics, avoid }).build();
    root.add(this.beachDressing.group);
    this.interactables.push(...this.props.interactables);
  }

  // ---------------------------------------------------------------------------
  // Lighting & atmosphere
  // ---------------------------------------------------------------------------
  _createSun() {
    const { azimuthDeg, elevationDeg } = WORLD.sun;
    const az = THREE.MathUtils.degToRad(azimuthDeg);
    const el = THREE.MathUtils.degToRad(elevationDeg);
    this.sunDir = new THREE.Vector3(Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el)).normalize();
    sharedUniforms.uSunDir.value.copy(this.sunDir);
    heightFogUniforms.uHFogSunDir.value.copy(this.sunDir);

    // Warm key light. Shadows: 4096² map over ±40 m (≈2 cm texels) following
    // the focus; small depth bias + normal bias kill acne on slopes without
    // detaching contact shadows (peter-panning). Penumbra comes from the
    // contact-hardening PCF patch (lighting/ShaderPatches.js).
    this.sun = new THREE.DirectionalLight(PALETTE.sun, 2.75);
    this.sun.castShadow = true;
    const s = this.sun.shadow;
    const S = RENDER.shadow;
    s.mapSize.set(RENDER.shadowMapSize, RENDER.shadowMapSize);
    s.camera.left = s.camera.bottom = -RENDER.shadowFrustum;
    s.camera.right = s.camera.top = RENDER.shadowFrustum;
    s.camera.near = S.near;
    s.camera.far = S.far;
    s.bias = S.bias;
    s.normalBias = S.normalBias;
    s.radius = S.radius;
    this.root.add(this.sun, this.sun.target);
  }

  _createAtmosphere() {
    const { scene } = this.engine;
    // Distance fog in exactly the sky's horizon colour → seamless horizon;
    // height fog (shader patch) thickens the haze at low altitude.
    scene.fog = new THREE.FogExp2(sharedUniforms.uSkyHorizon.value.clone(), RENDER.fogDensity);
    scene.background = sharedUniforms.uSkyHorizon.value.clone();
    const H = RENDER.heightFog;
    heightFogUniforms.uHFogDensity.value = H.density;
    heightFogUniforms.uHFogFalloff.value = H.falloff;
    heightFogUniforms.uHFogBase.value = H.base;
    heightFogUniforms.uHFogColor.value.copy(sharedUniforms.uSkyHorizon.value).multiplyScalar(1.02);
    heightFogUniforms.uHFogSunColor.value.copy(sharedUniforms.uSunColor.value);
  }

  /**
   * Image-based lighting from the procedural sky (replaces the old hemisphere
   * light). Call again after changing the sun / sky colours.
   */
  _createIBL() {
    const { scene, renderer } = this.engine;
    this.ibl ??= new SkyIBL(renderer, {
      size: RENDER.ibl.size,
      exposure: RENDER.ibl.exposure,
      groundBounce: RENDER.ibl.groundBounce,
    });
    scene.environment = this.ibl.update();
    scene.environmentIntensity = RENDER.ibl.intensity;
  }

  refreshLighting() {
    sharedUniforms.uSunDir.value.copy(this.sunDir);
    heightFogUniforms.uHFogSunDir.value.copy(this.sunDir);
    this._createIBL();
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
    this.vfx.update(dt, renderTime, this.focus);
  }

  lateUpdate(dt) {
    this.sky.update(this.engine.camera);
    this.cityDressing.update(dt, this.engine.camera.position);
  }

  /**
   * Centres the orthographic shadow frustum on the focus point and snaps it
   * to whole shadow-map texels in light space, which removes the shimmering
   * ("swimming") of shadow edges as the player moves.
   */
  _updateShadowCamera() {
    const texel = (2 * RENDER.shadowFrustum) / RENDER.shadowMapSize;
    _rot.lookAt(ORIGIN, _v.copy(this.sunDir).negate(), UP);
    _rotInv.copy(_rot).invert();
    _v.copy(this.focus).applyMatrix4(_rotInv);
    _v.x = Math.round(_v.x / texel) * texel;
    _v.y = Math.round(_v.y / texel) * texel;
    _v.applyMatrix4(_rot);
    this.sun.target.position.copy(_v);
    this.sun.position.copy(_v).addScaledVector(this.sunDir, (RENDER.shadow.near + RENDER.shadow.far) / 2);
    this.sun.target.updateMatrixWorld();
  }
}

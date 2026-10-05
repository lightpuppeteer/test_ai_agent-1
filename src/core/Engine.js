import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { SMAAPass } from 'three/addons/postprocessing/SMAAPass.js';
import { LUTPass } from 'three/addons/postprocessing/LUTPass.js';
import { GradingShader } from '../shaders/grading.glsl.js';
import { StylizedAOPass } from '../lighting/StylizedAOPass.js';
import { createJusantLUT } from '../lighting/JusantLUT.js';
import { installShaderPatches } from '../lighting/ShaderPatches.js';
import { PHYSICS, RENDER } from '../config.js';

/**
 * Engine — owns the renderer, scene, camera, post-processing chain and the
 * main loop. Gameplay code plugs in as "systems" (plain objects/classes) that
 * implement any of these optional hooks:
 *
 *   fixedUpdate(dt, simTime)   // before each physics step (forces, KCC, vehicles)
 *   postPhysics(dt, simTime)   // after each physics step (read back results)
 *   update(dt, renderTime)     // once per rendered frame (gameplay, animation)
 *   lateUpdate(dt, renderTime) // after update (camera, cloth, UI)
 *
 * Physics runs at a fixed rate with an accumulator; rendered transforms are
 * interpolated between the last two physics states (see PhysicsWorld), and
 * `renderTime` is the matching interpolated simulation time so that shaders
 * (e.g. the Gerstner ocean) stay in lock-step with physics (buoyancy).
 *
 * Post-processing (all in one EffectComposer):
 *
 *   RenderPass (HDR, + depth texture)
 *   → StylizedAOPass   depth-reconstructed ambient obscurance (linear HDR)
 *   → UnrealBloomPass  very soft, high threshold (sun, glints, lanterns)
 *   → GradingPass      saturation/contrast, vignette, grain (linear HDR)
 *   → OutputPass       tone mapping (Neutral) + sRGB
 *   → LUTPass          Jusant warm/cool creative grade (display space)
 *   → SMAAPass         edge anti-aliasing on the final image
 */
export class Engine {
  /**
   * @param {object} opts
   * @param {HTMLElement} opts.container
   * @param {import('./PhysicsWorld.js').PhysicsWorld} opts.physics
   */
  constructor({ container, physics }) {
    this.container = container;
    this.physics = physics;

    // Global shader chunk overrides (soft shadows, height fog) must be in
    // place before any material compiles.
    const S = RENDER.shadow;
    installShaderPatches({
      shadowTaps: S.taps,
      shadowDepthRange: S.far - S.near,
      shadowTexelWorld: (2 * RENDER.shadowFrustum) / RENDER.shadowMapSize,
      lightAngle: S.lightAngle,
    });

    // --- Renderer -----------------------------------------------------------
    this.renderer = new THREE.WebGLRenderer({
      antialias: false, // SMAA runs at the end of the composer chain
      powerPreference: 'high-performance',
      stencil: false,
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, RENDER.maxPixelRatio));
    this.renderer.setSize(container.clientWidth, container.clientHeight);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    // Khronos PBR Neutral keeps authored hues & saturation (ideal for a
    // painted palette) while still rolling off HDR highlights (sun, glints).
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.renderer.toneMappingExposure = RENDER.exposure;
    this.renderer.shadowMap.enabled = true;
    // three r186 removed PCFSoftShadowMap (it now logs a warning and falls back
    // to PCF). Softness comes from our contact-hardening PCF patch instead.
    this.renderer.shadowMap.type = THREE.PCFShadowMap;
    container.appendChild(this.renderer.domElement);

    // --- Scene & camera -----------------------------------------------------
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(55, container.clientWidth / container.clientHeight, 0.1, 2000);
    this.camera.position.set(0, 6, -30);

    this._createPostProcessing(container.clientWidth, container.clientHeight);

    // --- Loop state ---------------------------------------------------------
    this.systems = [];
    this.fixedDt = PHYSICS.fixedTimeStep;
    this.maxSubSteps = PHYSICS.maxSubSteps; // quality/perf knob, tunable at runtime
    this.simTime = 0;
    this.renderTime = 0;
    this.alpha = 0;
    this.frame = 0;
    this._accumulator = 0;
    this._lastNow = -1;
    this._running = false;
    this.stats = { fps: 0, frameMs: 0, physicsSteps: 0 };
    this._fpsAccum = 0;
    this._fpsFrames = 0;

    this._onResize = this._onResize.bind(this);
    this._tick = this._tick.bind(this);
    window.addEventListener('resize', this._onResize);
    document.addEventListener('visibilitychange', () => {
      // Drop the time spent in a background tab instead of simulating it.
      this._lastNow = -1;
    });
  }

  _createPostProcessing(width, height) {
    // Composer targets carry a depth texture so the AO pass can read the
    // beauty pass depth (shader-displaced geometry included).
    const size = this.renderer.getDrawingBufferSize(new THREE.Vector2());
    const rt = new THREE.WebGLRenderTarget(size.x, size.y, {
      type: THREE.HalfFloatType,
      depthTexture: new THREE.DepthTexture(size.x, size.y),
    });
    this.composer = new EffectComposer(this.renderer, rt);
    this.composer.setPixelRatio(this.renderer.getPixelRatio());

    const P = (this.passes = {});
    P.render = new RenderPass(this.scene, this.camera);
    P.ao = new StylizedAOPass(this.camera, RENDER.ao);
    P.ao.enabled = RENDER.ao.enabled;
    P.bloom = new UnrealBloomPass(
      new THREE.Vector2(width, height),
      RENDER.bloom.strength,
      RENDER.bloom.radius,
      RENDER.bloom.threshold,
    );
    P.grading = new ShaderPass(GradingShader);
    const g = RENDER.grading;
    const gu = P.grading.uniforms;
    gu.uSaturation.value = g.saturation;
    gu.uContrast.value = g.contrast;
    gu.uShadowTint.value = new THREE.Vector3(...g.shadowTint);
    gu.uHighlightTint.value = new THREE.Vector3(...g.highlightTint);
    gu.uVignette.value = g.vignette;
    gu.uGrain.value = g.grain;
    P.output = new OutputPass(); // tone mapping + sRGB
    P.lut = new LUTPass({ lut: createJusantLUT(RENDER.lut.size), intensity: RENDER.lut.intensity });
    P.lut.enabled = RENDER.lut.enabled;
    P.smaa = new SMAAPass();
    P.smaa.enabled = RENDER.antialias === 'smaa';

    for (const pass of [P.render, P.ao, P.bloom, P.grading, P.output, P.lut, P.smaa]) this.composer.addPass(pass);
    this.composer.setSize(width, height);
    // Backwards-compatible aliases.
    this.renderPass = P.render;
    this.bloomPass = P.bloom;
    this.gradingPass = P.grading;
  }

  /**
   * Registers a system. Lower `order` runs first in every phase.
   * Returns the system for chaining.
   */
  addSystem(system, order = 0) {
    system.__order = order;
    this.systems.push(system);
    this.systems.sort((a, b) => a.__order - b.__order);
    return system;
  }

  removeSystem(system) {
    const i = this.systems.indexOf(system);
    if (i >= 0) this.systems.splice(i, 1);
  }

  start() {
    if (this._running) return;
    this._running = true;
    this.renderer.setAnimationLoop(this._tick);
  }

  stop() {
    this._running = false;
    this.renderer.setAnimationLoop(null);
  }

  _tick(nowMs) {
    const now = nowMs / 1000;
    let frameDt = this._lastNow < 0 ? this.fixedDt : now - this._lastNow;
    this._lastNow = now;
    frameDt = Math.min(Math.max(frameDt, 0), 0.25);

    // --- Fixed-step simulation ---------------------------------------------
    this._accumulator += frameDt;
    let steps = 0;
    const dt = this.fixedDt;
    while (this._accumulator >= dt && steps < this.maxSubSteps) {
      for (const s of this.systems) s.fixedUpdate?.(dt, this.simTime);
      this.physics.step();
      this.simTime += dt;
      for (const s of this.systems) s.postPhysics?.(dt, this.simTime);
      this.physics.capture();
      this._accumulator -= dt;
      steps++;
    }
    if (steps === this.maxSubSteps) this._accumulator = Math.min(this._accumulator, dt);
    this.stats.physicsSteps = steps;

    // --- Interpolated presentation ----------------------------------------
    this.alpha = this._accumulator / dt;
    this.physics.interpolate(this.alpha);
    // The rendered physics state sits between (simTime - dt) and simTime.
    this.renderTime = Math.max(0, this.simTime - dt + this.alpha * dt);

    for (const s of this.systems) s.update?.(frameDt, this.renderTime);
    for (const s of this.systems) s.lateUpdate?.(frameDt, this.renderTime);

    this.gradingPass.uniforms.uTime.value = this.renderTime;
    this.composer.render(frameDt);
    this.frame++;

    // --- Stats ---------------------------------------------------------------
    this._fpsAccum += frameDt;
    this._fpsFrames++;
    if (this._fpsAccum >= 0.5) {
      this.stats.fps = Math.round(this._fpsFrames / this._fpsAccum);
      this.stats.frameMs = (this._fpsAccum / this._fpsFrames) * 1000;
      this._fpsAccum = 0;
      this._fpsFrames = 0;
    }
  }

  _onResize() {
    const w = this.container.clientWidth;
    const h = this.container.clientHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
    this.composer.setPixelRatio(this.renderer.getPixelRatio());
    this.composer.setSize(w, h);
  }

  dispose() {
    this.stop();
    window.removeEventListener('resize', this._onResize);
    this.composer.dispose();
    this.renderer.dispose();
  }
}

import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { GradingShader } from '../shaders/grading.glsl.js';
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

    // --- Renderer -----------------------------------------------------------
    this.renderer = new THREE.WebGLRenderer({
      antialias: false, // MSAA happens in the composer's render target
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
    this.renderer.shadowMap.type = THREE.PCFShadowMap; // soft via light.shadow.radius
    container.appendChild(this.renderer.domElement);

    // --- Scene & camera -----------------------------------------------------
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(55, container.clientWidth / container.clientHeight, 0.1, 2000);
    this.camera.position.set(0, 6, -30);

    // --- Post-processing ----------------------------------------------------
    const size = this.renderer.getDrawingBufferSize(new THREE.Vector2());
    const rt = new THREE.WebGLRenderTarget(size.x, size.y, {
      type: THREE.HalfFloatType,
      samples: RENDER.msaaSamples,
    });
    this.composer = new EffectComposer(this.renderer, rt);
    this.composer.setPixelRatio(this.renderer.getPixelRatio());
    this.composer.setSize(container.clientWidth, container.clientHeight);

    this.renderPass = new RenderPass(this.scene, this.camera);
    this.bloomPass = new UnrealBloomPass(
      new THREE.Vector2(container.clientWidth, container.clientHeight),
      RENDER.bloom.strength,
      RENDER.bloom.radius,
      RENDER.bloom.threshold,
    );
    this.gradingPass = new ShaderPass(GradingShader);
    const g = RENDER.grading;
    const gu = this.gradingPass.uniforms;
    gu.uSaturation.value = g.saturation;
    gu.uContrast.value = g.contrast;
    gu.uShadowTint.value = new THREE.Vector3(...g.shadowTint);
    gu.uHighlightTint.value = new THREE.Vector3(...g.highlightTint);
    gu.uVignette.value = g.vignette;
    gu.uGrain.value = g.grain;

    this.composer.addPass(this.renderPass);
    this.composer.addPass(this.bloomPass);
    this.composer.addPass(this.gradingPass);
    this.composer.addPass(new OutputPass()); // tone mapping + sRGB

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

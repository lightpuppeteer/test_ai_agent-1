import { PhysicsWorld } from './core/PhysicsWorld.js';
import { Engine } from './core/Engine.js';
import { Input } from './core/Input.js';
import { CameraRig } from './core/CameraRig.js';
import { ChapterManager } from './core/ChapterManager.js';
import { HUD } from './ui/HUD.js';
import { ShoreChapter } from './chapters/ShoreChapter.js';

/**
 * Bootstrap: physics (WASM) → engine → global services (input, camera, HUD)
 * → chapter. Each chapter owns its world, systems and physics scope.
 */
async function boot() {
  const status = document.getElementById('loading-status');
  const setStatus = (t) => {
    status.textContent = t;
    return new Promise((r) => requestAnimationFrame(() => r()));
  };

  await setStatus('Initialising physics…');
  const physics = await PhysicsWorld.create();

  const engine = new Engine({ container: document.getElementById('app'), physics });
  const input = new Input(engine.renderer.domElement);
  const hud = new HUD();
  const cameraRig = new CameraRig(engine.camera, input, physics);

  // Global systems (persist across chapters).
  engine.addSystem(
    {
      update() {
        input.beginFrame();
        if (input.consume('debugPhysics')) physics.setDebugVisible(engine.scene, !physics.debugVisible);
        if (input.consume('toggleHelp')) hud.toggleHelp();
        physics.updateDebug();
      },
    },
    -100,
  );
  engine.addSystem(cameraRig, 50);
  engine.addSystem({ lateUpdate: (dt) => hud.update(dt, engine) }, 100);

  const chapters = new ChapterManager({ engine, physics, input, hud, cameraRig });
  chapters.register('shore', () => new ShoreChapter());

  await setStatus('Building the old town…');
  await chapters.load('shore');

  // Compile shaders up-front to avoid hitches on first sight.
  await engine.renderer.compileAsync(engine.scene, engine.camera);

  engine.start();
  hud.show();
  requestAnimationFrame(() => document.getElementById('loading').classList.add('is-done'));

  // Handy for debugging from the console / automated tests.
  window.__game = { engine, physics, input, chapters, cameraRig, hud };
}

boot().catch((err) => {
  console.error(err);
  document.getElementById('loading-status').textContent = `Failed to start: ${err.message}`;
});

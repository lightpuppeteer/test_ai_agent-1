import * as THREE from 'three';

/**
 * Chapters are self-contained slices of the game (a beach, a cliff, a town…).
 * A chapter builds its content under `this.root`, registers its systems via
 * `this.addSystem()` and creates physics objects while its physics scope is
 * active — so unloading it is a single call with no leaks.
 */
export class Chapter {
  constructor(id, title) {
    this.id = id;
    this.title = title;
    this.root = new THREE.Group();
    this.root.name = `chapter:${id}`;
    this.systems = [];
    this.scope = null;
    this.ctx = null;
  }

  /** Override: build the chapter. `ctx` = { engine, physics, input, hud }. */
  async load(_ctx) {}

  /** Override for custom teardown; call super.unload() last. */
  unload() {
    const { engine, physics } = this.ctx;
    for (const s of this.systems) {
      engine.removeSystem(s);
      s.dispose?.();
    }
    this.systems.length = 0;
    if (this.scope) physics.disposeScope(this.scope);
    this.root.removeFromParent();
    this.root.traverse((o) => {
      o.geometry?.dispose?.();
      const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
      for (const m of mats) m.dispose?.();
    });
  }

  addSystem(system, order = 0) {
    this.systems.push(system);
    return this.ctx.engine.addSystem(system, order);
  }
}

export class ChapterManager {
  constructor(ctx) {
    this.ctx = ctx;
    this.factories = new Map();
    this.current = null;
  }

  register(id, factory) {
    this.factories.set(id, factory);
    return this;
  }

  async load(id) {
    const factory = this.factories.get(id);
    if (!factory) throw new Error(`Unknown chapter "${id}"`);
    if (this.current) {
      this.current.unload();
      this.current = null;
    }
    const chapter = factory();
    chapter.ctx = this.ctx;
    this.ctx.engine.scene.add(chapter.root);
    chapter.scope = this.ctx.physics.pushScope();
    try {
      await chapter.load(this.ctx);
    } finally {
      this.ctx.physics.popScope();
    }
    this.current = chapter;
    return chapter;
  }
}

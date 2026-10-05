import * as THREE from 'three';
import { Chapter } from '../core/ChapterManager.js';
import { WORLD } from '../config.js';
import { Environment } from '../environment/Environment.js';
import { InteractionManager } from '../interaction/InteractionManager.js';
import { VehicleSystem } from '../vehicle/VehicleSystem.js';
import { CharacterController } from '../character/CharacterController.js';

/**
 * Chapter I — The Shore: beach, ocean and the old-town square.
 * A template for further chapters: build world → register interactables →
 * spawn vehicles → spawn the player → register systems in update order.
 */
export class ShoreChapter extends Chapter {
  constructor() {
    super('shore', 'Chapter I — The Shore');
  }

  async load(ctx) {
    const { engine, physics, input, hud, cameraRig } = ctx;

    this.environment = new Environment({ engine, physics, root: this.root }).build();

    this.interactions = new InteractionManager({ cellSize: 8 });
    for (const it of this.environment.interactables) this.interactions.register(it);
    this.interactions.onFocusChange((it) => hud.setPrompt(it));

    this.vehicles = new VehicleSystem({ physics, interactions: this.interactions, parent: this.root });
    const promenadeY = WORLD.promenade.height;
    this.vehicles.spawnCar(new THREE.Vector3(-8, promenadeY + 0.75, -48.6), Math.PI / 2);

    this.character = new CharacterController({
      physics,
      input,
      interactions: this.interactions,
      vehicles: this.vehicles,
      environment: this.environment,
      cameraRig,
      hud,
      parent: this.root,
      camera: engine.camera,
      spawn: WORLD.spawn,
    });

    // Update order: character (intent → FSM → KCC) → vehicles → environment
    // (buoyancy, wind, shadows). The camera (50) and HUD (100) are global.
    this.addSystem(this.character, 0);
    this.addSystem(this.vehicles, 10);
    this.addSystem(this.environment, 20);
  }
}

import { ParticleSystem, PARTICLE_TYPES } from './ParticleSystem.js';
import { WORLD } from '../config.js';

/**
 * Ambient life: emitters feeding the pooled ParticleSystem around the
 * camera focus, each gated by where the player is.
 *
 *  dust    everywhere — warm specks drifting downwind
 *  pollen  in the old town — slow, fluffy, near-neutral buoyancy
 *  spray   on the shore — droplets/bubbles flicked off breaking crests;
 *          spawned on the *actual* Gerstner surface and killed when they
 *          fall back into it
 *
 * Rates are per second; fractional emission is accumulated so rates stay
 * exact at any frame rate. Nothing allocates per frame.
 */
export class AtmosphereVFX {
  /**
   * @param {object} o
   * @param {import('../environment/WindSystem.js').WindSystem} o.wind
   * @param {import('../environment/GerstnerWaves.js').GerstnerWaves} o.waves
   * @param {(x:number, z:number) => number} o.groundHeightAt
   * @param {(x:number, z:number) => boolean} o.isCity
   */
  constructor({ wind, waves, groundHeightAt, isCity, capacity = 3000 }) {
    this.wind = wind;
    this.waves = waves;
    this.groundHeightAt = groundHeightAt;
    this.isCity = isCity;
    this.system = new ParticleSystem({ wind, capacity });
    this.mesh = this.system.mesh;
    this.time = 0;
    this.focus = { x: 0, y: 0, z: 0 };
    this.emitters = [
      { type: PARTICLE_TYPES.dust, rate: 90, acc: 0, spawn: (p) => this._spawnDust(p) },
      { type: PARTICLE_TYPES.pollen, rate: 45, acc: 0, spawn: (p) => this._spawnPollen(p) },
      { type: PARTICLE_TYPES.spray, rate: 320, acc: 0, spawn: (p) => this._spawnSpray(p) },
    ];
    const waterKill = (type, x, y, z) =>
      type === PARTICLE_TYPES.spray.id && y < this.waves.heightAt(x, z, this.time, null, 2) - 0.05;
    this.system.killTest = waterKill;
  }

  /** Emitter strength 0..1 given the focus position (where effects make sense). */
  _gate(type, f) {
    if (type === PARTICLE_TYPES.pollen) return this.isCity(f.x, f.z) ? 1 : 0;
    if (type === PARTICLE_TYPES.spray) {
      // Strongest when standing near the waterline; fades out up the beach.
      return Math.max(0, 1 - Math.max(0, 18 - f.z) / 30) * (f.z < WORLD.wadeLimitZ + 30 ? 1 : 0);
    }
    return 1;
  }

  update(dt, renderTime, focus) {
    this.time = renderTime;
    this.focus = focus;
    for (const e of this.emitters) {
      e.acc += e.rate * this._gate(e.type, focus) * (0.4 + 0.6 * this.wind.strength) * dt;
      let n = Math.floor(e.acc);
      e.acc -= n;
      while (n-- > 0) if (!e.spawn(focus)) break;
    }
    this.system.update(dt);
  }

  _spawnDust(f) {
    const W = this.wind;
    // Bias spawns upwind so specks drift through the view.
    const x = f.x + (Math.random() - 0.5) * 36 - W.direction.x * 8;
    const z = f.z + (Math.random() - 0.5) * 36 - W.direction.z * 8;
    const g = this.groundHeightAt(x, z);
    const y = g + 0.1 + Math.random() * Math.random() * 6;
    return this.system.emit(
      PARTICLE_TYPES.dust,
      x,
      y,
      z,
      W.direction.x * W.speed * 0.6,
      0,
      W.direction.z * W.speed * 0.6,
      4 + Math.random() * 4,
      0.025 + Math.random() * 0.035,
    );
  }

  _spawnPollen(f) {
    const a = Math.random() * Math.PI * 2;
    const r = 2 + Math.random() * 18;
    const x = f.x + Math.cos(a) * r;
    const z = f.z + Math.sin(a) * r;
    const y = this.groundHeightAt(x, z) + 0.4 + Math.random() * 4.5;
    return this.system.emit(
      PARTICLE_TYPES.pollen,
      x,
      y,
      z,
      0,
      0,
      0,
      7 + Math.random() * 6,
      0.045 + Math.random() * 0.04,
    );
  }

  _spawnSpray(f) {
    // Find a crest in the breaking zone near the focus (a few tries max).
    for (let attempt = 0; attempt < 3; attempt++) {
      const x = f.x + (Math.random() - 0.5) * 50;
      const z = 24 + Math.random() * 22;
      const h = this.waves.heightAt(x, z, this.time, null, 2);
      const ground = this.groundHeightAt(x, z);
      if (h - ground < 0.15) continue; // dry sand
      if (h < WORLD.waterLevel + 0.06 && Math.random() > 0.15) continue; // mostly from crests
      const W = this.wind;
      const up = 1.2 + Math.random() * 2.6;
      return this.system.emit(
        PARTICLE_TYPES.spray,
        x,
        h + 0.02,
        z,
        (Math.random() - 0.5) * 0.8 + W.direction.x * 1.5,
        up,
        (Math.random() - 0.5) * 0.8 + W.direction.z * 1.5 - 0.8,
        0.6 + Math.random() * 1.1,
        0.018 + Math.random() * 0.03,
      );
    }
    return true;
  }
}

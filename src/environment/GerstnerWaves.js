import * as THREE from 'three';
import { WORLD } from '../config.js';
import { sandHeight } from './Terrain.js';

const G = 9.81;
const TAU = Math.PI * 2;

/**
 * Wave spectrum. Directions are the direction of travel; angle 0 means
 * "rolling straight onto the beach" (towards -Z).
 *  - wavelength: metres (phase speed follows deep-water dispersion c = √(g/k))
 *  - steepness:  Q in [0,1]; ΣQ must stay < 1 or crests loop over themselves
 *  - amplitude is derived: A = Q / k  (classic Gerstner parameterisation)
 */
export const WAVE_SPECTRUM = [
  { angleDeg: 0, wavelength: 48, steepness: 0.08, phase: 0.0 },
  { angleDeg: 17, wavelength: 27, steepness: 0.1, phase: 1.9 },
  { angleDeg: -26, wavelength: 15, steepness: 0.11, phase: 4.1 },
  { angleDeg: 38, wavelength: 9.2, steepness: 0.11, phase: 2.7 },
  { angleDeg: -12, wavelength: 5.6, steepness: 0.09, phase: 5.3 },
  { angleDeg: 55, wavelength: 3.4, steepness: 0.07, phase: 0.9 },
];

export const OCEAN_LOD_CENTER = new THREE.Vector2(0, 25); // where the grid is densest
const SHORE = { minAtten: 0.12, depth: 4.5 };

/**
 * CPU mirror of the ocean vertex shader. Floating bodies sample the exact
 * same surface the GPU draws, so buoyancy matches what the player sees.
 *
 * Note on Gerstner sampling: Gerstner waves move vertices *horizontally* as
 * well as vertically, so the height "at" world (x,z) is the height of the
 * grid point p0 that ends up at (x,z) after displacement. We find p0 with a
 * few fixed-point iterations (converges quickly because ΣQ < 1).
 */
export class GerstnerWaves {
  constructor(spectrum = WAVE_SPECTRUM, { waterLevel = WORLD.waterLevel } = {}) {
    this.waterLevel = waterLevel;
    this.waves = spectrum.map((w) => {
      const a = THREE.MathUtils.degToRad(w.angleDeg);
      const k = TAU / w.wavelength;
      return {
        dx: Math.sin(a),
        dz: -Math.cos(a),
        k,
        c: Math.sqrt(G / k),
        steepness: w.steepness,
        wavelength: w.wavelength,
        phase: w.phase,
      };
    });
    // Uniform payloads for the ocean shader.
    this.uniformWaves = this.waves.map((w) => new THREE.Vector4(w.dx, w.dz, w.steepness, w.wavelength));
    this.uniformPhases = this.waves.map((w) => w.phase);
  }

  get count() {
    return this.waves.length;
  }

  /** Attenuation applied to every wave at undisplaced point (x,z): shallow water + LOD. */
  _shoreAtten(x, z) {
    const depth = this.waterLevel - sandHeight(x, z);
    const t = THREE.MathUtils.clamp(depth / SHORE.depth, 0, 1);
    return SHORE.minAtten + (1 - SHORE.minAtten) * t * t * (3 - 2 * t);
  }

  _lodFade(x, z, wavelength) {
    const dist = Math.hypot(x - OCEAN_LOD_CENTER.x, z - OCEAN_LOD_CENTER.y);
    const t = THREE.MathUtils.clamp((dist - 6 * wavelength) / (6 * wavelength), 0, 1);
    return 1 - t * t * (3 - 2 * t);
  }

  /**
   * Displacement of the grid point (x,z) at time t.
   * @param {THREE.Vector3} outDisp displacement (dx, dy, dz)
   * @param {THREE.Vector3} [outVel] surface particle velocity (m/s)
   */
  displacement(x, z, t, outDisp, outVel = null) {
    outDisp.set(0, 0, 0);
    if (outVel) outVel.set(0, 0, 0);
    const shore = this._shoreAtten(x, z);
    for (const w of this.waves) {
      const atten = shore * this._lodFade(x, z, w.wavelength);
      const A = (w.steepness / w.k) * atten;
      const f = w.k * (w.dx * x + w.dz * z - w.c * t) + w.phase;
      const cf = Math.cos(f);
      const sf = Math.sin(f);
      outDisp.x += w.dx * A * cf;
      outDisp.y += A * sf;
      outDisp.z += w.dz * A * cf;
      if (outVel) {
        const omega = w.k * w.c;
        outVel.x += w.dx * A * omega * sf;
        outVel.y += -A * omega * cf;
        outVel.z += w.dz * A * omega * sf;
      }
    }
    return outDisp;
  }

  /**
   * Water surface height (world Y) at world (x, z) and time t.
   * Optionally returns the surface velocity there (for drag / drift).
   */
  heightAt(x, z, t, outVel = null, iterations = 4) {
    let px = x;
    let pz = z;
    const d = _disp;
    for (let i = 0; i < iterations; i++) {
      this.displacement(px, pz, t, d);
      px = x - d.x;
      pz = z - d.z;
    }
    this.displacement(px, pz, t, d, outVel);
    return this.waterLevel + d.y;
  }

  /** GLSL implementation (requires sandHeight() and the uniforms declared below). */
  get glsl() {
    return /* glsl */ `
    #define WAVE_COUNT ${this.count}
    uniform vec4 uWaves[WAVE_COUNT];     // dir.xy, steepness, wavelength
    uniform float uWavePhases[WAVE_COUNT];
    uniform float uWaterLevel;
    uniform vec2 uLodCenter;

    float shoreAtten(vec2 p) {
      float depth = uWaterLevel - sandHeight(p);
      return mix(${SHORE.minAtten.toFixed(4)}, 1.0, smoothstep(0.0, ${SHORE.depth.toFixed(4)}, depth));
    }

    // Returns displacement; accumulates analytic tangent/binormal for normals
    // and the horizontal Jacobian (crest compression → foam).
    vec3 gerstner(vec2 p, float t, inout vec3 tangent, inout vec3 binormal, out float jacobian) {
      vec3 disp = vec3(0.0);
      float shore = shoreAtten(p);
      float dist = length(p - uLodCenter);
      for (int i = 0; i < WAVE_COUNT; i++) {
        vec4 w = uWaves[i];
        vec2 D = w.xy;
        float L = w.w;
        float k = 6.28318530718 / L;
        float c = sqrt(9.81 / k);
        float lod = 1.0 - smoothstep(6.0 * L, 12.0 * L, dist);
        float s = w.z * shore * lod;  // effective steepness (k·A)
        float A = s / k;
        float f = k * (dot(D, p) - c * t) + uWavePhases[i];
        float sf = sin(f);
        float cf = cos(f);
        disp += vec3(D.x * A * cf, A * sf, D.y * A * cf);
        tangent += vec3(-D.x * D.x * s * sf, D.x * s * cf, -D.x * D.y * s * sf);
        binormal += vec3(-D.x * D.y * s * sf, D.y * s * cf, -D.y * D.y * s * sf);
      }
      jacobian = tangent.x * binormal.z - tangent.z * binormal.x;
      return disp;
    }
    `;
  }
}

const _disp = new THREE.Vector3();

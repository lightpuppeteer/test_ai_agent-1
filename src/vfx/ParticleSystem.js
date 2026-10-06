import * as THREE from 'three';

/**
 * Pooled, instanced particle system (one draw call for every particle type).
 *
 * Memory layout is structure-of-arrays in pre-allocated typed arrays, and
 * the live set is kept *packed* at the front: spawning appends at `count`,
 * killing swaps the last live particle into the hole (O(1), no allocation,
 * no garbage). The InstancedMesh simply draws `count` instances, reading
 * per-instance position/size/alpha/type attributes that are re-uploaded
 * once per frame for the live range only.
 *
 * Simulation is CPU-side (a few thousand particles is ~0.2 ms) so particles
 * can react to gameplay data: the global wind, wave heights, ground height.
 */
export class ParticlePool {
  constructor(capacity) {
    this.capacity = capacity;
    this.count = 0;
    this.pos = new Float32Array(capacity * 3);
    this.vel = new Float32Array(capacity * 3);
    this.age = new Float32Array(capacity);
    this.life = new Float32Array(capacity);
    this.size = new Float32Array(capacity);
    this.seed = new Float32Array(capacity);
    this.type = new Uint8Array(capacity);
  }

  /** Reserves a slot; returns its index or -1 when the pool is exhausted. */
  spawn() {
    if (this.count >= this.capacity) return -1;
    const i = this.count++;
    this.age[i] = 0;
    return i;
  }

  /** Frees slot `i` by moving the last live particle into it. */
  kill(i) {
    const last = --this.count;
    if (i === last) return;
    this.pos.copyWithin(i * 3, last * 3, last * 3 + 3);
    this.vel.copyWithin(i * 3, last * 3, last * 3 + 3);
    this.age[i] = this.age[last];
    this.life[i] = this.life[last];
    this.size[i] = this.size[last];
    this.seed[i] = this.seed[last];
    this.type[i] = this.type[last];
  }
}

/**
 * Particle behaviour per type. `wind` scales how strongly a particle is
 * carried by the global wind; `drag` is how quickly it adopts the air
 * velocity (1/s); `lift` counters gravity (pollen floats, spray falls).
 */
export const PARTICLE_TYPES = {
  dust: { id: 0, wind: 0.9, drag: 1.6, gravity: -0.12, turbulence: 0.5, alpha: 0.5 },
  pollen: { id: 1, wind: 0.55, drag: 0.9, gravity: 0.02, turbulence: 0.9, alpha: 0.85 },
  spray: { id: 2, wind: 0.6, drag: 0.35, gravity: -6.5, turbulence: 0.2, alpha: 0.9 },
};
const TYPE_LIST = Object.values(PARTICLE_TYPES);

export class ParticleSystem {
  /**
   * @param {object} o
   * @param {import('../environment/WindSystem.js').WindSystem} o.wind
   * @param {number} [o.capacity]
   */
  constructor({ wind, capacity = 3000 }) {
    this.wind = wind;
    this.pool = new ParticlePool(capacity);
    this.time = 0;
    /** Optional per-particle kill test, e.g. spray hitting the water: (type, x, y, z) => bool */
    this.killTest = null;

    const geometry = new THREE.PlaneGeometry(1, 1);
    this.aOffset = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 3), 3).setUsage(
      THREE.DynamicDrawUsage,
    );
    this.aData = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 4), 4).setUsage(THREE.DynamicDrawUsage);
    geometry.setAttribute('aOffset', this.aOffset);
    geometry.setAttribute('aData', this.aData);

    const material = new THREE.ShaderMaterial({
      name: 'AtmosphereParticles',
      transparent: true,
      depthWrite: false,
      uniforms: {
        uColors: { value: [new THREE.Color(0xfff0d0), new THREE.Color(0xfff6c4), new THREE.Color(0xf4fbff)] },
      },
      vertexShader: /* glsl */ `
        attribute vec3 aOffset;
        attribute vec4 aData; // size, alpha, type, spin
        varying vec2 vUv;
        varying float vAlpha;
        varying float vType;
        void main() {
          vec4 mv = viewMatrix * vec4(aOffset, 1.0);
          float c = cos(aData.w), s = sin(aData.w);
          vec2 q = mat2(c, -s, s, c) * position.xy;
          mv.xy += q * aData.x;
          gl_Position = projectionMatrix * mv;
          vUv = uv;
          vType = aData.z;
          // Fade very close (no screen-filling blobs) and far away.
          float d = -mv.z;
          vAlpha = aData.y * smoothstep(0.4, 1.6, d) * (1.0 - smoothstep(35.0, 60.0, d));
        }
      `,
      fragmentShader: /* glsl */ `
        uniform vec3 uColors[3];
        varying vec2 vUv;
        varying float vAlpha;
        varying float vType;
        void main() {
          vec2 p = vUv - 0.5;
          float r = length(p) * 2.0;
          float a;
          vec3 col;
          if (vType < 0.5) {            // dust: soft speck
            a = smoothstep(1.0, 0.1, r);
            col = uColors[0];
          } else if (vType < 1.5) {     // pollen: bright core + fuzzy halo
            a = smoothstep(1.0, 0.55, r) * 0.45 + smoothstep(0.45, 0.0, r);
            col = uColors[1] * 1.4;
          } else {                      // spray bubble: bright rim, clear centre, glint
            float rim = smoothstep(1.0, 0.82, r) * smoothstep(0.45, 0.8, r);
            float glint = smoothstep(0.35, 0.0, length(p - vec2(-0.14, 0.14)) * 2.0);
            a = rim * 0.85 + glint + 0.12 * smoothstep(1.0, 0.0, r);
            col = uColors[2] * 1.6;
          }
          a *= vAlpha;
          if (a < 0.004) discard;
          gl_FragColor = vec4(col, a);
          #include <colorspace_fragment>
        }
      `,
    });

    this.mesh = new THREE.InstancedMesh(geometry, material, capacity);
    this.mesh.count = 0;
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 12;
    this.mesh.name = 'AtmosphereParticles';
  }

  /**
   * Emits one particle. Returns false when the pool is full (callers simply
   * skip — VFX degrades gracefully instead of allocating).
   */
  emit(type, x, y, z, vx, vy, vz, life, size) {
    const P = this.pool;
    const i = P.spawn();
    if (i < 0) return false;
    P.pos[i * 3] = x;
    P.pos[i * 3 + 1] = y;
    P.pos[i * 3 + 2] = z;
    P.vel[i * 3] = vx;
    P.vel[i * 3 + 1] = vy;
    P.vel[i * 3 + 2] = vz;
    P.life[i] = life;
    P.size[i] = size;
    P.seed[i] = Math.random() * 100;
    P.type[i] = type.id;
    return true;
  }

  update(dt) {
    this.time += dt;
    const P = this.pool;
    const W = this.wind;
    const wx = W.direction.x * W.speed;
    const wz = W.direction.z * W.speed;
    const t = this.time;
    const off = this.aOffset.array;
    const data = this.aData.array;

    let i = 0;
    while (i < P.count) {
      const age = (P.age[i] += dt);
      const life = P.life[i];
      if (age >= life) {
        P.kill(i);
        continue; // slot i now holds a different live particle
      }
      const T = TYPE_LIST[P.type[i]];
      const s = P.seed[i];
      const k = i * 3;
      // Air velocity = global wind + cheap per-particle eddies.
      const tx = Math.sin(t * 1.3 + s * 7.1) * T.turbulence;
      const ty = Math.sin(t * 0.9 + s * 3.7) * T.turbulence * 0.5;
      const tz = Math.cos(t * 1.1 + s * 5.3) * T.turbulence;
      const ax = wx * T.wind + tx;
      const az = wz * T.wind + tz;
      const drag = Math.min(1, T.drag * dt);
      P.vel[k] += (ax - P.vel[k]) * drag;
      P.vel[k + 1] += (ty - P.vel[k + 1]) * drag * 0.5 + T.gravity * dt;
      P.vel[k + 2] += (az - P.vel[k + 2]) * drag;
      P.pos[k] += P.vel[k] * dt;
      P.pos[k + 1] += P.vel[k + 1] * dt;
      P.pos[k + 2] += P.vel[k + 2] * dt;
      if (this.killTest && this.killTest(P.type[i], P.pos[k], P.pos[k + 1], P.pos[k + 2])) {
        P.kill(i);
        continue;
      }

      // Write render attributes (packed: index i == instance i).
      const u = age / life;
      const fade = Math.min(1, u * 6) * Math.min(1, (1 - u) * 3);
      off[k] = P.pos[k];
      off[k + 1] = P.pos[k + 1];
      off[k + 2] = P.pos[k + 2];
      const d = i * 4;
      data[d] = P.size[i] * (T.id === 2 ? 1 - u * 0.4 : 1);
      data[d + 1] = fade * T.alpha;
      data[d + 2] = T.id;
      data[d + 3] = s + t * (T.id === 1 ? 0.6 : 0.2);
      i++;
    }

    this.mesh.count = P.count;
    if (P.count > 0) {
      this.aOffset.clearUpdateRanges();
      this.aOffset.addUpdateRange(0, P.count * 3);
      this.aOffset.needsUpdate = true;
      this.aData.clearUpdateRanges();
      this.aData.addUpdateRange(0, P.count * 4);
      this.aData.needsUpdate = true;
    }
  }
}

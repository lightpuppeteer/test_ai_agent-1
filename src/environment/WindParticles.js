import * as THREE from 'three';
import { sharedUniforms, SHARED_UNIFORMS_GLSL, NOISE_GLSL } from '../shaders/common.glsl.js';

/**
 * Two fully GPU-animated wind effects (zero per-frame CPU work besides
 * updating a few uniforms):
 *
 *  1. Dust & sand motes — points wrapped in a box that follows the camera
 *     focus and drift with the *integrated* wind offset, so gust changes
 *     never make particles jump.
 *  2. Wind streaks — Jusant-style curling ribbons. Each instance is a
 *     camera-facing strip whose vertices are laid along an analytic path
 *     (downwind travel + lateral meander + an optional loop). Every life
 *     cycle re-seeds the spawn position with a hash of the cycle index.
 */
export class WindParticles {
  constructor({ moteCount = 1400, streakCount = 34, motes = true } = {}) {
    this.group = new THREE.Group();
    this.group.name = 'WindParticles';
    this.center = new THREE.Vector3();

    // Motes are optional: the pooled instanced AtmosphereVFX can take over dust.
    this.motes = motes ? this._createMotes(moteCount) : null;
    this.streaks = this._createStreaks(streakCount);
    if (this.motes) this.group.add(this.motes);
    this.group.add(this.streaks);
  }

  _createMotes(count) {
    const geometry = new THREE.BufferGeometry();
    const pos = new Float32Array(count * 3);
    const seed = new Float32Array(count * 4);
    for (let i = 0; i < count; i++) {
      pos.set([Math.random(), Math.random(), Math.random()], i * 3);
      seed.set([Math.random(), Math.random(), Math.random(), Math.random()], i * 4);
    }
    geometry.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geometry.setAttribute('aSeed', new THREE.BufferAttribute(seed, 4));

    const material = new THREE.ShaderMaterial({
      name: 'WindMotes',
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      uniforms: {
        ...sharedUniforms,
        uCenter: { value: this.center },
        uBox: { value: new THREE.Vector3(56, 12, 56) },
        uSize: { value: 0.11 },
        uViewportHeight: { value: 900 }, // drawing-buffer pixels
        uColor: { value: new THREE.Color(0xfff1d6) },
      },
      vertexShader: /* glsl */ `
        ${SHARED_UNIFORMS_GLSL}
        attribute vec4 aSeed;
        uniform vec3 uCenter;
        uniform vec3 uBox;
        uniform float uSize;
        uniform float uViewportHeight;
        varying float vAlpha;
        void main() {
          vec3 p = position * uBox;
          p += uWindOffset * (0.65 + 0.7 * aSeed.x);
          p += vec3(sin(uTime * 0.7 + aSeed.y * 20.0),
                    sin(uTime * 0.9 + aSeed.z * 17.0) * 0.5,
                    cos(uTime * 0.6 + aSeed.w * 13.0)) * 0.7;
          vec3 c = uCenter + vec3(0.0, uBox.y * 0.35, 0.0);
          vec3 rel = mod(p - c + uBox * 0.5, uBox) - uBox * 0.5;
          vec3 e = abs(rel) / (uBox * 0.5);
          float edge = 1.0 - smoothstep(0.65, 1.0, max(max(e.x, e.y), e.z));
          vec4 mv = viewMatrix * vec4(c + rel, 1.0);
          gl_Position = projectionMatrix * mv;
          float sizeWorld = uSize * (0.35 + aSeed.w);
          gl_PointSize = sizeWorld * projectionMatrix[1][1] * uViewportHeight * 0.5 / max(-mv.z, 0.1);
          float twinkle = 0.6 + 0.4 * sin(uTime * (1.5 + aSeed.y * 3.0) + aSeed.x * 40.0);
          vAlpha = edge * twinkle * (0.25 + 0.75 * uWindStrength) * smoothstep(0.3, 2.0, -mv.z);
        }
      `,
      fragmentShader: /* glsl */ `
        uniform vec3 uColor;
        varying float vAlpha;
        void main() {
          float d = length(gl_PointCoord - 0.5);
          float a = smoothstep(0.5, 0.05, d) * vAlpha * 0.55;
          if (a < 0.003) discard;
          gl_FragColor = vec4(uColor, a); // AdditiveBlending = src·α + dst
          #include <colorspace_fragment>
        }
      `,
    });
    const points = new THREE.Points(geometry, material);
    points.frustumCulled = false;
    points.renderOrder = 10;
    points.name = 'WindMotes';
    return points;
  }

  _createStreaks(count) {
    const segments = 40;
    const base = new THREE.InstancedBufferGeometry();
    const uv = new Float32Array((segments + 1) * 2 * 2);
    const index = [];
    for (let i = 0; i <= segments; i++) {
      const u = i / segments;
      uv.set([u, -1, u, 1], i * 4);
      if (i < segments) {
        const a = i * 2;
        index.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
      }
    }
    base.setAttribute('aUV', new THREE.BufferAttribute(uv, 2));
    // `position` is required by three.js; the shader ignores it.
    base.setAttribute('position', new THREE.BufferAttribute(new Float32Array((segments + 1) * 2 * 3), 3));
    base.setIndex(index);
    const seeds = new Float32Array(count * 4);
    for (let i = 0; i < count; i++) seeds.set([Math.random(), Math.random(), Math.random(), Math.random()], i * 4);
    base.setAttribute('aSeed', new THREE.InstancedBufferAttribute(seeds, 4));
    base.instanceCount = count;

    const material = new THREE.ShaderMaterial({
      name: 'WindStreaks',
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
      uniforms: {
        ...sharedUniforms,
        uCenter: { value: this.center },
        uRadius: { value: 26 },
        uLength: { value: 7.5 },
        uWidth: { value: 0.045 },
        uOpacity: { value: 0.32 },
        uColor: { value: new THREE.Color(0xfff6e8) },
      },
      vertexShader: /* glsl */ `
        ${SHARED_UNIFORMS_GLSL}
        ${NOISE_GLSL}
        attribute vec2 aUV;
        attribute vec4 aSeed;
        uniform vec3 uCenter;
        uniform float uRadius;
        uniform float uLength;
        uniform float uWidth;
        varying float vAlpha;
        varying float vV;

        vec3 pathPoint(vec3 origin, float s, vec3 W, vec3 S, vec3 U, vec4 r, float loopAt) {
          float a1 = 0.4 + r.x * 1.1;
          float f1 = 0.18 + r.y * 0.3;
          vec3 p = origin + W * s;
          p += S * sin(s * f1 + r.w * 6.283) * a1;
          p += U * cos(s * f1 * 0.7 + r.x * 6.283) * a1 * 0.35;
          // Prolate-cycloid loop (k > 1) gives the signature curl.
          if (r.z > 0.45) {
            float R = 0.45 + r.y * 0.6;
            float th = clamp((s - loopAt) / R, 0.0, 6.2831853);
            float k = 1.7;
            p += (-W * sin(th) + U * (1.0 - cos(th))) * (k * R);
          }
          return p;
        }

        void main() {
          float period = 3.2 + aSeed.y * 2.6;
          float cyc = uTime / period + aSeed.w;
          float life = fract(cyc);
          float id = floor(cyc);
          vec4 r = vec4(styHash12(vec2(id, aSeed.x * 97.0)),
                        styHash12(vec2(aSeed.y * 53.0, id)),
                        styHash12(vec2(id * 1.3, aSeed.z * 71.0)),
                        styHash12(vec2(aSeed.w * 37.0, id * 0.7)));

          vec3 W = normalize(uWindDir + vec3(0.0, 0.0001, 0.0));
          vec3 U = vec3(0.0, 1.0, 0.0);
          vec3 S = normalize(cross(U, W));

          // Spawn upwind of the focus so streaks sweep through the view.
          float speed = 3.0 + 9.0 * uWindStrength;
          float travel = speed * period;
          vec3 origin = uCenter
            + S * (r.x - 0.5) * 2.0 * uRadius
            + W * ((r.y - 0.5) * uRadius - travel * 0.5)
            + U * mix(0.4, 5.5, r.z * r.z);

          float headS = life * travel;
          float s = headS - aUV.x * uLength;
          float loopAt = travel * (0.25 + 0.4 * r.w);
          vec3 p = pathPoint(origin, s, W, S, U, r, loopAt);
          vec3 p2 = pathPoint(origin, s + 0.08, W, S, U, r, loopAt);
          vec3 T = normalize(p2 - p + vec3(1e-5));
          vec3 toCam = normalize(cameraPosition - p);
          vec3 side = normalize(cross(T, toCam));
          float taper = sin(3.14159 * clamp(aUV.x, 0.0, 1.0));
          p += side * aUV.y * uWidth * (0.4 + taper);

          float lifeFade = smoothstep(0.0, 0.18, life) * (1.0 - smoothstep(0.7, 1.0, life));
          float trail = pow(1.0 - aUV.x, 1.3) * smoothstep(0.0, 0.08, aUV.x);
          float born = smoothstep(0.0, 1.5, s);
          float dist = length(cameraPosition - p);
          float distFade = smoothstep(4.0, 9.0, dist) * (1.0 - smoothstep(30.0, 65.0, dist));
          vAlpha = lifeFade * trail * born * distFade * (0.3 + 0.7 * uWindStrength);
          vV = aUV.y;
          gl_Position = projectionMatrix * viewMatrix * vec4(p, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        uniform vec3 uColor;
        uniform float uOpacity;
        varying float vAlpha;
        varying float vV;
        void main() {
          float a = vAlpha * uOpacity * (1.0 - vV * vV);
          if (a < 0.002) discard;
          gl_FragColor = vec4(uColor, a); // AdditiveBlending = src·α + dst
          #include <colorspace_fragment>
        }
      `,
    });
    const mesh = new THREE.Mesh(base, material);
    mesh.frustumCulled = false;
    mesh.renderOrder = 11;
    mesh.name = 'WindStreaks';
    return mesh;
  }

  /**
   * @param {THREE.Vector3} focus world point the effects should surround
   * @param {number} viewportHeight drawing-buffer height in pixels
   */
  update(focus, viewportHeight) {
    this.center.copy(focus);
    if (this.motes) this.motes.material.uniforms.uViewportHeight.value = viewportHeight;
  }
}

import * as THREE from 'three';
import { PALETTE } from '../config.js';
import { sharedUniforms, SHARED_UNIFORMS_GLSL, NOISE_GLSL, SKY_GLSL } from '../shaders/common.glsl.js';
import { SAND_HEIGHT_GLSL } from './Terrain.js';
import { OCEAN_LOD_CENTER } from './GerstnerWaves.js';

/**
 * Stylised Gerstner ocean.
 *
 * Vertex: N Gerstner waves (shared spectrum with the CPU buoyancy sampler),
 *   attenuated in shallow water (depth from the analytic sand height) and
 *   faded per-wavelength with distance from the dense grid centre (LOD,
 *   mirrored on the CPU too). Analytic tangent/binormal → normals, and the
 *   horizontal Jacobian → crest-compression foam.
 *
 * Fragment: depth-tinted body colour (shallow turquoise → deep teal), fresnel
 *   sky reflection using the *same* sky gradient as the dome, back-lit
 *   subsurface glow through crests, soft + sharp sun glints, painterly crest
 *   foam, animated shoreline foam bands, and alpha that thins out in the
 *   shallows so the wet sand shows through.
 */
export class Ocean {
  /** @param {import('./GerstnerWaves.js').GerstnerWaves} waves */
  constructor(waves) {
    this.waves = waves;
    this.mesh = new THREE.Mesh(this._createGeometry(), this._createMaterial());
    this.mesh.name = 'Ocean';
    this.mesh.frustumCulled = false; // displaced in the shader; covers the horizon
    this.mesh.renderOrder = 5;
    this.mesh.matrixAutoUpdate = false;
  }

  /**
   * Graded grid: ~0.7 m spacing near the beach / centre, growing cubically to
   * several metres towards the horizon (where fog hides the detail anyway).
   */
  _createGeometry({ halfWidth = 700, length = 900, segX = 280, segZ = 240, z0 = 12 } = {}) {
    const xs = [];
    const zs = [];
    const ax = 0.18;
    const az = 0.2;
    for (let i = 0; i <= segX; i++) {
      const u = (i / segX) * 2 - 1;
      const au = Math.abs(u);
      xs.push(Math.sign(u) * halfWidth * (ax * au + (1 - ax) * au * au * au) + OCEAN_LOD_CENTER.x);
    }
    for (let j = 0; j <= segZ; j++) {
      const v = j / segZ;
      zs.push(z0 + length * (az * v + (1 - az) * v * v * v));
    }
    const positions = new Float32Array(xs.length * zs.length * 3);
    let k = 0;
    for (let j = 0; j < zs.length; j++) {
      for (let i = 0; i < xs.length; i++) {
        positions[k++] = xs[i];
        positions[k++] = 0;
        positions[k++] = zs[j];
      }
    }
    const indices = [];
    const row = xs.length;
    for (let j = 0; j < segZ; j++) {
      for (let i = 0; i < segX; i++) {
        const a = j * row + i;
        const b = a + 1;
        const c = a + row;
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    g.setIndex(indices);
    return g;
  }

  _createMaterial() {
    const w = this.waves;
    // Note: UniformsUtils.merge/clone would copy the shared uniforms; spread
    // them instead so sun/wind/time stay shared by reference.
    const uniforms = {
      ...THREE.UniformsUtils.clone(THREE.UniformsLib.fog),
      ...sharedUniforms,
      uWaves: { value: w.uniformWaves },
      uWavePhases: { value: w.uniformPhases },
      uWaterLevel: { value: w.waterLevel },
      uLodCenter: { value: OCEAN_LOD_CENTER },
      uDeep: { value: new THREE.Color(PALETTE.oceanDeep) },
      uMid: { value: new THREE.Color(PALETTE.oceanMid) },
      uShallow: { value: new THREE.Color(PALETTE.oceanShallow) },
      uFoam: { value: new THREE.Color(PALETTE.foam) },
    };
    return new THREE.ShaderMaterial({
      name: 'Ocean',
      transparent: true,
      depthWrite: true,
      fog: true,
      lights: false,
      uniforms,
      vertexShader: /* glsl */ `
        ${SHARED_UNIFORMS_GLSL}
        ${SAND_HEIGHT_GLSL}
        ${w.glsl}
        varying vec3 vWorldPos;
        varying vec3 vNormal;
        varying float vJacobian;
        varying float vHeight;
        #include <fog_pars_vertex>

        void main() {
          vec3 grid = (modelMatrix * vec4(position, 1.0)).xyz;
          vec3 tangent = vec3(1.0, 0.0, 0.0);
          vec3 binormal = vec3(0.0, 0.0, 1.0);
          float jac;
          vec3 disp = gerstner(grid.xz, uTime, tangent, binormal, jac);
          vec3 wp = vec3(grid.x, uWaterLevel, grid.z) + disp;
          vWorldPos = wp;
          vNormal = normalize(cross(binormal, tangent));
          vJacobian = jac;
          vHeight = disp.y;
          vec4 mvPosition = viewMatrix * vec4(wp, 1.0);
          gl_Position = projectionMatrix * mvPosition;
          #include <fog_vertex>
        }
      `,
      fragmentShader: /* glsl */ `
        ${SHARED_UNIFORMS_GLSL}
        ${NOISE_GLSL}
        ${SKY_GLSL}
        ${SAND_HEIGHT_GLSL}
        uniform float uWaterLevel;
        uniform vec3 uDeep;
        uniform vec3 uMid;
        uniform vec3 uShallow;
        uniform vec3 uFoam;
        varying vec3 vWorldPos;
        varying vec3 vNormal;
        varying float vJacobian;
        varying float vHeight;
        #include <fog_pars_fragment>

        // Wind-driven capillary ripples as an analytic normal perturbation.
        vec2 rippleGradient(vec2 p, float t) {
          vec2 g = vec2(0.0);
          vec2 wd = normalize(uWindDir.xz + vec2(1e-4));
          for (int i = 0; i < 4; i++) {
            float fi = float(i);
            float ang = (fi - 1.5) * 0.55;
            vec2 d = vec2(wd.x * cos(ang) - wd.y * sin(ang), wd.x * sin(ang) + wd.y * cos(ang));
            float k = 3.2 + fi * 2.1;
            float a = 0.018 / (1.0 + fi * 0.6);
            float ph = dot(d, p) * k - t * sqrt(9.81 * k) * 0.6 + fi * 1.7;
            g += d * (a * k * cos(ph));
          }
          return g * (0.5 + uWindStrength);
        }

        void main() {
          vec3 V = normalize(cameraPosition - vWorldPos);
          float dist = length(cameraPosition - vWorldPos);

          vec3 N = normalize(vNormal);
          vec2 rg = rippleGradient(vWorldPos.xz, uTime) * (1.0 - smoothstep(25.0, 140.0, dist));
          N = normalize(N + vec3(-rg.x, 0.0, -rg.y));
          if (dot(N, V) < 0.0) N = normalize(N + V * (-dot(N, V) + 0.02)); // avoid back-facing normals

          // --- Depth-based body colour ------------------------------------
          float floorY = sandHeight(vWorldPos.xz);
          float depth = max(vWorldPos.y - floorY, 0.0);
          vec3 body = mix(uShallow, uMid, smoothstep(0.2, 3.5, depth));
          body = mix(body, uDeep, smoothstep(3.5, 22.0, depth));

          float ndl = max(dot(N, uSunDir), 0.0);
          vec3 lit = body * (0.6 + 0.4 * ndl) * mix(vec3(1.0), uSunColor, 0.35);

          // Back-lit glow through thin crests.
          float sss = pow(max(dot(V, -uSunDir), 0.0), 3.0) * smoothstep(-0.3, 0.7, vHeight);
          lit += uShallow * uSunColor * sss * 0.65;

          // --- Reflection ----------------------------------------------------
          vec3 R = reflect(-V, N);
          R.y = abs(R.y);
          vec3 refl = stySkyColor(normalize(R), false);
          float fres = 0.02 + 0.98 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
          vec3 col = mix(lit, refl, clamp(fres * 0.9, 0.0, 0.9));

          // --- Sun glints: a tight sparkle + a broad painted sheen ------------
          vec3 H = normalize(uSunDir + V);
          float nh = max(dot(N, H), 0.0);
          col += uSunColor * (pow(nh, 420.0) * 7.0 + pow(nh, 48.0) * 0.14);

          // --- Foam ---------------------------------------------------------
          vec2 fp = vWorldPos.xz;
          float fn = styFbm2(fp * 0.33 + uWindOffset.xz * 0.03 + vec2(uTime * 0.03));
          float fn2 = styNoise2(fp * 2.4 - uTime * 0.25);
          float crest = smoothstep(0.92, 0.55, vJacobian) * smoothstep(0.35, 0.75, fn + fn2 * 0.3);
          float shoreEdge = (1.0 - smoothstep(0.0, 0.18, depth)) * smoothstep(0.35, 0.65, fn + 0.15);
          float bands = sin(depth * 6.0 - uTime * 1.2 + fn * 7.0) * 0.5 + 0.5;
          float shoreBands = smoothstep(0.78, 0.92, bands) * (1.0 - smoothstep(0.1, 1.2, depth)) * smoothstep(0.35, 0.7, fn2);
          float foam = clamp(max(crest, max(shoreEdge * 0.9, shoreBands * 0.6)), 0.0, 1.0);
          vec3 foamCol = uFoam * (0.62 + 0.38 * ndl) * mix(vec3(1.0), uSunColor, 0.45) + uSkyZenith * 0.06;
          col = mix(col, foamCol, foam);

          // --- Alpha: clear shallows, soft contact with the sand -------------
          float alpha = mix(0.42, 0.96, smoothstep(0.0, 2.4, depth));
          alpha = max(alpha, foam * 0.95);
          alpha *= smoothstep(0.0, 0.05, depth);

          gl_FragColor = vec4(col, alpha);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
          #include <fog_fragment>
        }
      `,
    });
  }
}

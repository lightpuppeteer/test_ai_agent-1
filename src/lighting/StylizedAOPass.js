import * as THREE from 'three';
import { Pass, FullScreenQuad } from 'three/addons/postprocessing/Pass.js';

/**
 * Screen-space ambient obscurance from the *beauty pass depth buffer*.
 *
 * Unlike SSAO/GTAO passes that re-render the scene with an override
 * material, this reads the depth the RenderPass already produced. That
 * matters here: the dunes, waves and wind sway are displaced in vertex
 * shaders, and an override material would not see that displacement.
 *
 * Pipeline (half resolution by default):
 *   1. AO   — normals reconstructed from depth, spiral samples within a
 *             world-space radius (Alchemy/SAO estimator), distance falloff
 *   2. Blur — separable, depth-aware (bilateral) 2-pass blur
 *   3. Mix  — colour × AO, applied in linear HDR before bloom/tone mapping
 *
 * Requires the composer's render targets to carry a DepthTexture.
 */
export class StylizedAOPass extends Pass {
  constructor(camera, { radius = 0.85, intensity = 0.85, bias = 0.025, samples = 12, scale = 0.5 } = {}) {
    super();
    this.camera = camera;
    this.scale = scale;
    this.needsSwap = true;

    const rtOpts = { type: THREE.HalfFloatType, format: THREE.RGBAFormat, depthBuffer: false };
    this.aoTarget = new THREE.WebGLRenderTarget(1, 1, rtOpts);
    this.blurTarget = new THREE.WebGLRenderTarget(1, 1, rtOpts);

    const common = /* glsl */ `
      #include <packing>
      uniform sampler2D tDepth;
      uniform float cameraNear;
      uniform float cameraFar;
      uniform mat4 cameraProjectionMatrix;
      uniform mat4 cameraInverseProjectionMatrix;
      float viewZ(vec2 uv) {
        return perspectiveDepthToViewZ(texture2D(tDepth, uv).x, cameraNear, cameraFar);
      }
      vec3 viewPos(vec2 uv) {
        float z = viewZ(uv);
        vec4 clip = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
        vec4 v = cameraInverseProjectionMatrix * clip;
        v.xyz /= v.w;
        return v.xyz * (z / v.z);
      }
    `;
    const cameraUniforms = () => ({
      tDepth: { value: null },
      cameraNear: { value: 0.1 },
      cameraFar: { value: 1000 },
      cameraProjectionMatrix: { value: new THREE.Matrix4() },
      cameraInverseProjectionMatrix: { value: new THREE.Matrix4() },
    });
    const vertexShader = /* glsl */ `
      varying vec2 vUv;
      void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
    `;

    this.aoMaterial = new THREE.ShaderMaterial({
      name: 'StylizedAO',
      defines: { SAMPLES: samples },
      uniforms: {
        ...cameraUniforms(),
        uRadius: { value: radius },
        uBias: { value: bias },
        uResolution: { value: new THREE.Vector2() },
      },
      vertexShader,
      fragmentShader: /* glsl */ `
        ${common}
        uniform float uRadius;
        uniform float uBias;
        uniform vec2 uResolution;
        varying vec2 vUv;
        float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
        void main() {
          float depth = texture2D(tDepth, vUv).x;
          if (depth >= 1.0) { gl_FragColor = vec4(1.0); return; }
          vec3 P = viewPos(vUv);
          // Normal from the smaller-gradient neighbours (robust at silhouettes).
          vec2 px = 1.0 / uResolution;
          vec3 pr = viewPos(vUv + vec2(px.x, 0.0)) - P;
          vec3 pl = P - viewPos(vUv - vec2(px.x, 0.0));
          vec3 pu = viewPos(vUv + vec2(0.0, px.y)) - P;
          vec3 pd = P - viewPos(vUv - vec2(0.0, px.y));
          vec3 dx = abs(pr.z) < abs(pl.z) ? pr : pl;
          vec3 dy = abs(pu.z) < abs(pd.z) ? pu : pd;
          vec3 N = normalize(cross(dx, dy));

          // Project the world radius to a screen radius.
          float screenR = uRadius * cameraProjectionMatrix[1][1] * 0.5 / -P.z;
          screenR = min(screenR, 0.12);
          float angle = ign(gl_FragCoord.xy) * 6.2831853;
          float occlusion = 0.0;
          for (int i = 0; i < SAMPLES; i++) {
            float t = (float(i) + 0.5) / float(SAMPLES);
            float a = angle + float(i) * 2.399963;
            vec2 o = vec2(cos(a), sin(a)) * t * screenR * vec2(uResolution.y / uResolution.x, 1.0);
            vec3 S = viewPos(vUv + o);
            vec3 v = S - P;
            float vv = dot(v, v);
            float vn = dot(v, N);
            float falloff = max(0.0, 1.0 - vv / (uRadius * uRadius));
            occlusion += max(0.0, vn - uBias * -P.z) / (vv + 0.01) * falloff;
          }
          float ao = clamp(1.0 - 2.0 * occlusion / float(SAMPLES), 0.0, 1.0);
          gl_FragColor = vec4(vec3(ao), 1.0);
        }
      `,
    });

    this.blurMaterial = new THREE.ShaderMaterial({
      name: 'StylizedAOBlur',
      uniforms: {
        ...cameraUniforms(),
        tAO: { value: null },
        uDirection: { value: new THREE.Vector2(1, 0) },
        uResolution: { value: new THREE.Vector2() },
      },
      vertexShader,
      fragmentShader: /* glsl */ `
        ${common}
        uniform sampler2D tAO;
        uniform vec2 uDirection;
        uniform vec2 uResolution;
        varying vec2 vUv;
        void main() {
          float z0 = viewZ(vUv);
          float sum = 0.0;
          float wsum = 0.0;
          for (int i = -4; i <= 4; i++) {
            vec2 uv = vUv + uDirection * float(i) / uResolution;
            float w = exp(-float(i * i) / 8.0);
            float dz = abs(viewZ(uv) - z0) / max(-z0, 0.1);
            w *= max(0.0, 1.0 - dz * 18.0); // depth-aware: don't bleed across edges
            sum += texture2D(tAO, uv).r * w;
            wsum += w;
          }
          gl_FragColor = vec4(vec3(sum / max(wsum, 1e-4)), 1.0);
        }
      `,
    });

    this.compositeMaterial = new THREE.ShaderMaterial({
      name: 'StylizedAOComposite',
      uniforms: {
        tDiffuse: { value: null },
        tAO: { value: null },
        uIntensity: { value: intensity },
      },
      vertexShader,
      fragmentShader: /* glsl */ `
        uniform sampler2D tDiffuse;
        uniform sampler2D tAO;
        uniform float uIntensity;
        varying vec2 vUv;
        void main() {
          vec4 c = texture2D(tDiffuse, vUv);
          float ao = texture2D(tAO, vUv).r;
          // Tint occlusion slightly cool, like sky light failing to reach.
          vec3 occ = mix(vec3(1.0), vec3(ao) * vec3(0.94, 0.97, 1.03), uIntensity);
          gl_FragColor = vec4(c.rgb * min(occ, vec3(1.0)), c.a);
        }
      `,
    });

    this.quad = new FullScreenQuad(null);
  }

  get intensity() {
    return this.compositeMaterial.uniforms.uIntensity.value;
  }

  set intensity(v) {
    this.compositeMaterial.uniforms.uIntensity.value = v;
  }

  setSize(width, height) {
    const w = Math.max(1, Math.round(width * this.scale));
    const h = Math.max(1, Math.round(height * this.scale));
    this.aoTarget.setSize(w, h);
    this.blurTarget.setSize(w, h);
    this.aoMaterial.uniforms.uResolution.value.set(w, h);
    this.blurMaterial.uniforms.uResolution.value.set(w, h);
  }

  _syncCamera(material, depthTexture) {
    const u = material.uniforms;
    u.tDepth.value = depthTexture;
    u.cameraNear.value = this.camera.near;
    u.cameraFar.value = this.camera.far;
    u.cameraProjectionMatrix.value.copy(this.camera.projectionMatrix);
    u.cameraInverseProjectionMatrix.value.copy(this.camera.projectionMatrixInverse);
  }

  render(renderer, writeBuffer, readBuffer) {
    const depth = readBuffer.depthTexture;
    if (!depth) throw new Error('StylizedAOPass needs a DepthTexture on the composer targets');

    this._syncCamera(this.aoMaterial, depth);
    this._syncCamera(this.blurMaterial, depth);

    // 1. AO
    this.quad.material = this.aoMaterial;
    renderer.setRenderTarget(this.aoTarget);
    this.quad.render(renderer);

    // 2. Bilateral blur (H then V)
    this.quad.material = this.blurMaterial;
    this.blurMaterial.uniforms.tAO.value = this.aoTarget.texture;
    this.blurMaterial.uniforms.uDirection.value.set(1, 0);
    renderer.setRenderTarget(this.blurTarget);
    this.quad.render(renderer);
    this.blurMaterial.uniforms.tAO.value = this.blurTarget.texture;
    this.blurMaterial.uniforms.uDirection.value.set(0, 1);
    renderer.setRenderTarget(this.aoTarget);
    this.quad.render(renderer);

    // 3. Composite
    this.quad.material = this.compositeMaterial;
    this.compositeMaterial.uniforms.tDiffuse.value = readBuffer.texture;
    this.compositeMaterial.uniforms.tAO.value = this.aoTarget.texture;
    renderer.setRenderTarget(this.renderToScreen ? null : writeBuffer);
    this.quad.render(renderer);
  }

  dispose() {
    this.aoTarget.dispose();
    this.blurTarget.dispose();
    this.aoMaterial.dispose();
    this.blurMaterial.dispose();
    this.compositeMaterial.dispose();
    this.quad.dispose();
  }
}

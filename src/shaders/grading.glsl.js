/**
 * Colour-grading post pass (runs in linear HDR, before OutputPass tone-maps).
 *
 * The goal is the "illustrated" Jusant feel rather than photographic realism:
 *  - split-toning: cool shadows, warm highlights
 *  - gentle saturation / contrast around a mid-grey pivot
 *  - soft vignette and a whisper of animated grain to break up banding in the
 *    large smooth gradients (sky, fog) that this art style relies on.
 */
export const GradingShader = {
  name: 'GradingShader',
  uniforms: {
    tDiffuse: { value: null },
    uTime: { value: 0 },
    uSaturation: { value: 1.0 },
    uContrast: { value: 1.0 },
    uShadowTint: { value: [1, 1, 1] },
    uHighlightTint: { value: [1, 1, 1] },
    uVignette: { value: 0.3 },
    uGrain: { value: 0.02 },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform float uTime;
    uniform float uSaturation;
    uniform float uContrast;
    uniform vec3 uShadowTint;
    uniform vec3 uHighlightTint;
    uniform float uVignette;
    uniform float uGrain;
    varying vec2 vUv;

    float hash12(vec2 p) {
      vec3 p3 = fract(vec3(p.xyx) * 0.1031);
      p3 += dot(p3, p3.yzx + 33.33);
      return fract((p3.x + p3.y) * p3.z);
    }

    void main() {
      vec4 src = texture2D(tDiffuse, vUv);
      vec3 c = src.rgb;

      float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));

      // Split toning — weight by a smooth luminance ramp in log-ish space.
      float t = smoothstep(0.02, 0.9, luma / (1.0 + luma));
      c *= mix(uShadowTint, uHighlightTint, t);

      // Saturation around luminance.
      c = mix(vec3(luma), c, uSaturation);

      // Contrast around 18% grey (keeps HDR highlights intact).
      c = max(vec3(0.0), 0.18 * pow(max(c, vec3(1e-5)) / 0.18, vec3(uContrast)));

      // Vignette — elliptical, very soft.
      vec2 q = vUv - 0.5;
      float v = 1.0 - uVignette * smoothstep(0.25, 0.95, dot(q, q) * 2.2);
      c *= v;

      // Triangular-ish grain, scaled down in the highlights.
      float n = hash12(gl_FragCoord.xy + fract(uTime * 13.37) * 512.0)
              + hash12(gl_FragCoord.yx * 1.37 + fract(uTime * 7.31) * 256.0) - 1.0;
      c += n * uGrain * (0.25 + 0.75 * (1.0 - t)) * max(luma, 0.05);

      gl_FragColor = vec4(c, src.a);
    }
  `,
};

import * as Patterns from './Patterns.js';

/**
 * Texture synthesis worker: generates one baked set per message and
 * transfers the buffers back (zero-copy). Keeps several seconds of
 * per-pixel work off the main thread at startup.
 */
self.onmessage = ({ data }) => {
  const { id, fn, options } = data;
  try {
    const r = Patterns[fn](options);
    self.postMessage({ id, S: r.S, albedo: r.albedo, detail: r.detail }, [r.albedo.buffer, r.detail.buffer]);
  } catch (error) {
    self.postMessage({ id, error: String(error) });
  }
};

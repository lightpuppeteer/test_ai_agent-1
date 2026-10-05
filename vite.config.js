import { defineConfig } from 'vite';

// @dimforge/rapier3d-compat ships its WASM inlined as base64, so no WASM
// plugin is required. We only exclude it from dependency pre-bundling to
// keep dev-server cold starts fast (the module is large and already ESM).
export default defineConfig({
  optimizeDeps: {
    exclude: ['@dimforge/rapier3d-compat'],
  },
  build: {
    target: 'es2022',
    // Rapier's compat build inlines its WASM (~4 MB raw, ~1.7 MB gzip) and is
    // lazy-loaded in its own chunk by PhysicsWorld.create().
    chunkSizeWarningLimit: 4500,
  },
});

import { defineConfig } from 'astro/config';
import preact from '@astrojs/preact';
import AstroPWA from '@vite-pwa/astro';
import tailwindcss from '@tailwindcss/vite';

const BASE = process.env.BASE_URL ?? '/';
const BASE_NO_TRAIL = BASE.replace(/\/$/, '');

function crossOriginIsolation() {
  return {
    name: 'cross-origin-isolation',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
        res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
        next();
      });
    },
  };
}

export default defineConfig({
  srcDir: './app',
  base: BASE,
  server: { port: parseInt(process.env.PORT || '8080'), strictPort: true },
  devToolbar: { enabled: false },  // Prevents weird 404
  integrations: [
    preact(),
    AstroPWA({
      registerType: 'autoUpdate',
      injectRegister: false, // we register manually in Base.astro
      manifest: false,       // existing /manifest.json is shipped from /public
      workbox: {
        // Precache the whole app so first offline load works
        globPatterns: [
          '**/*.{html,js,css,wasm,pck,png,svg,ico,json,woff,woff2}',
        ],
        navigateFallback: `${BASE_NO_TRAIL}/play`,
        navigateFallbackDenylist: [
          /\/(rest|auth|storage|realtime)\/v1\//,
          // Vite HMR (and any token-bearing handshake) — never serve cached.
          /[?&]token=/,
        ],
        cleanupOutdatedCaches: true,
        // pck files can be large — bump from 2 MiB default
        maximumFileSizeToCacheInBytes: 200 * 1024 * 1024,
        runtimeCaching: [
          // Never cache Supabase
          {
            urlPattern: /\/(rest|auth|storage|realtime)\/v1\//,
            handler: 'NetworkOnly',
          },
          // Never cache Vite HMR / any token-authenticated handshake
          {
            urlPattern: ({ url }) => url.searchParams.has('token'),
            handler: 'NetworkOnly',
          },
          // Everything else: try network, fall back to cache when offline/slow
          {
            urlPattern: ({ url }) => url.origin === self.location.origin,
            handler: 'NetworkFirst',
            options: {
              cacheName: 'app',
              networkTimeoutSeconds: 3,
            },
          },
        ],
      },
      // devOptions: {
      //   enabled: false, // keep SW out of dev to avoid cache surprises while iterating
      // },
    }),
  ],
  vite: {
    envPrefix: ['PUBLIC_'],
    plugins: [tailwindcss(), crossOriginIsolation()],
    server: {
      watch: {
        usePolling: true,
        interval: 1000,
        ignored: ['**/public/godot/**'],
      },
    },
  },
  outDir: '../server/public',
});

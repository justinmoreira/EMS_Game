import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';
import preact from '@astrojs/preact';
import AstroPWA from '@vite-pwa/astro';
import tailwindcss from '@tailwindcss/vite';

const OUT_DIR = fileURLToPath(new URL('../server/public/', import.meta.url));

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
  base: process.env.BASE_URL ?? '/',
  server: { port: parseInt(process.env.PORT || '8080'), strictPort: true },
  devToolbar: { enabled: false },  // Prevents weird 404
  integrations: [
    preact(),
    AstroPWA({
      registerType: 'autoUpdate',
      manifest: false,
      workbox: {
        globDirectory: OUT_DIR,
        swDest: `${OUT_DIR}sw.js`,
        globPatterns: [
          '**/*.{js,wasm,pck,css,html,svg,png,ico,woff2,json}',
        ],
        navigateFallback: '/',
        maximumFileSizeToCacheInBytes: 50 * 1024 * 1024,
      },
      devOptions: { enabled: false },
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

import { fileURLToPath } from 'node:url';
import { watchFile } from 'node:fs';
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

// HMR for the Godot build: server-side watches public/godot/index.pck and
// pushes Vite's full-reload over its existing HMR WebSocket on rebuild.
// Replaces the client-side setInterval that was HEAD-polling index.pck every
// 2s from every page — no browser ping, just one WS message per rebuild.
// watchFile() polls (1s) on the server rather than using fs.watch/inotify
// because the dev tree on WSL lives under /mnt/c, where inotify isn't reliable
// (same reason Justfile's watchexec runs with --poll).
function godotHmr() {
  return {
    name: 'godot-hmr',
    configureServer(server) {
      const pck = fileURLToPath(
        new URL('./public/godot/index.pck', import.meta.url),
      );
      watchFile(pck, { interval: 1000 }, (curr, prev) => {
        if (curr.mtimeMs !== prev.mtimeMs) {
          server.ws.send({ type: 'full-reload', path: '*' });
        }
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
        // Two reasons a route is kept off the `/` fallback:
        //   • Game-canvas routes (/sandbox, /godot/*) must serve their OWN
        //     page or the canvas never mounts — they're precached, so they
        //     still work offline; they just must not get the `/` fallback.
        //   • Multiplayer (/multiplayer*) must always reach the live server,
        //     so it gets neither the fallback nor a precache entry (see
        //     globIgnores) — offline it fails fast, which is intended.
        navigateFallbackDenylist: [/^\/play/, /^\/multiplayer/, /^\/godot\//],
        // Offline support for the whole game EXCEPT multiplayer: precache
        // everything but the multiplayer pages, so sandbox / singleplayer /
        // tutorial / leaderboards work offline while multiplayer requires a
        // connection. registerType:'autoUpdate' keeps it fresh when online.
        globIgnores: ['**/multiplayer/**'],
        maximumFileSizeToCacheInBytes: 50 * 1024 * 1024,
        clientsClaim: false,
        skipWaiting: false,
      },
      devOptions: { enabled: false },
    }),
  ],
  vite: {
    envPrefix: ['PUBLIC_'],
    plugins: [tailwindcss(), crossOriginIsolation(), godotHmr()],
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

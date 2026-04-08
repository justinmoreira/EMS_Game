import { defineConfig } from 'astro/config';
import preact from '@astrojs/preact';
import tailwindcss from '@tailwindcss/vite';

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
  integrations: [preact()],
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

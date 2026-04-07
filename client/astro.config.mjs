import { defineConfig } from 'astro/config';
import preact from '@astrojs/preact';
import node from '@astrojs/node';
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
  output: 'server',
  adapter: node({ mode: 'standalone' }),
  server: { port: 8080, strictPort: false },
  integrations: [preact()],
  vite: {
    envPrefix: ['PUBLIC_'],
    plugins: [tailwindcss(), crossOriginIsolation()],
    server: {
      watch: {
        ignored: ['**/public/godot/**'],
      },
    },
  },
  outDir: '../server/public',
});

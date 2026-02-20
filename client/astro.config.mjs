import { defineConfig } from 'astro/config';
import preact from '@astrojs/preact';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  srcDir: './app',
  server: { port: 8080 },
  integrations: [preact()],
  vite: {
    plugins: [tailwindcss()],
    server: {},
  },
  outDir: '../server/public',
});

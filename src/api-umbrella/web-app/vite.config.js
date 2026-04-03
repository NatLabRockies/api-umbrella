import { defineConfig } from 'vite';

export default defineConfig({
  appType: 'custom',
  build: {
    manifest: true,
    copyPublicDir: false,
    rollupOptions: {
      input: './assets/login.js',
    },
  },
})

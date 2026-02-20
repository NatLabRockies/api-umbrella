import { defineConfig } from 'vite';
import { extensions, classicEmberSupport, ember } from '@embroider/vite';
import { babel } from '@rollup/plugin-babel';

export default defineConfig({
  plugins: [
    classicEmberSupport(),
    ember(),
    babel({
      babelHelpers: 'runtime',
      extensions,
    }),
  ],
  build: {
    rollupOptions: {
      external: ['require'],
    },
    chunkSizeWarningLimit: 800,
  },
  optimizeDeps: {
    exclude: ['ember-inflector'],
  },
});

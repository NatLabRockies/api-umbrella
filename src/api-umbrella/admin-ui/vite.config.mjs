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
      external: ['jquery'],
    },
  },
  resolve: {
    alias: {
      jquery: 'jquery',
    },
  },
  optimizeDeps: {
    exclude: ['jquery'],
  },
});

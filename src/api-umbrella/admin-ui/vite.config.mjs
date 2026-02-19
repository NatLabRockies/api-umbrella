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
      external: (id) => {
        // Externalize jquery, require, and all @ember/* packages
        return id === 'jquery' || id === 'require' || id.startsWith('@ember/');
      },
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
  css: {
    // Ensure dynamic or runtime-generated CSS files are properly handled
    preprocessorOptions: {
      scss: {
        additionalData: '@import "@/styles/globals.scss";', // Example path if SCSS is used
      },
    },
  },
});

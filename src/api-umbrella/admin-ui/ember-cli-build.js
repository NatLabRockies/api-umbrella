'use strict';

const EmberApp = require('ember-cli/lib/broccoli/ember-app');
const sass = require('sass');
const autoprefixer = require('autoprefixer');

module.exports = function(defaults) {
  const app = new EmberApp(defaults, {
    autoImport: {
      alias: {
        'jQuery-QueryBuilder': 'jQuery-QueryBuilder/dist/js/query-builder.standalone',
        diff: 'diff/dist/diff',
        inflection: 'inflection/lib/inflection',
        numeral: 'numeral/numeral',
        selectize: 'selectize/dist/js/standalone/selectize',
      },

      webpack: {
        externals: { jquery: 'jQuery' },
      },
    },

    sourcemaps: {
      // Always enable sourcemaps, even for the production build.
      enabled: true,
    },

    sassOptions: {
      implementation: sass,

      // The Sass number precision must be increased to 8 for Bootstrap, or
      // else certain things don't line up:
      // https://github.com/twbs/bootstrap-sass#sass-number-precision
      precision: 8,
    },

    postcssOptions: {
      compile: {
        enabled: false,
        map: false,
      },
      filter: {
        enabled: true,
        plugins: [
          {
            module: autoprefixer,
          },
        ],
        exclude: ['**/*.css.map'],
      },
    },

    /*
    babel: {
      plugins: [require.resolve('@babel/plugin-transform-class-static-block')]
    },
    */

    'ember-cli-babel': {
      includePolyfill: true,
    },

    'ember-bootstrap': {
      'bootstrapVersion': 5,
      'importBootstrapFont': false,
      'importBootstrapCSS': false,
    },

    'ember-simple-auth': {
      useSessionSetupMethod: true,
    },
  });

  return app.toTree();
};

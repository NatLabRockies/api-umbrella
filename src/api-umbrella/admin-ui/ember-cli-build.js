'use strict';
const EmberApp = require('ember-cli/lib/broccoli/ember-app');
const { compatBuild } = require('@embroider/compat');
const sass = require('sass');
const autoprefixer = require('autoprefixer');

module.exports = async function(defaults) {
  const {
    buildOnce
  } = await import("@embroider/vite");

  let app = new EmberApp(defaults, {
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

    'ember-cli-babel': {
      includePolyfill: true,
    },

    //todo: ask Nick about this
    'ember-bootstrap': {
      bootstrapVersion: 4,
      importBootstrapFont: false,
      importBootstrapCSS: false,
    },

    'ember-simple-auth': {
      useSessionSetupMethod: true,
    },

    emberData: {
      deprecations: {
        // New projects can safely leave this deprecation disabled.
        // If upgrading, to opt-into the deprecated behavior, set this to true and then follow:
        // https://deprecations.emberjs.com/id/ember-data-deprecate-store-extends-ember-object
        // before upgrading to Ember Data 6.0
        DEPRECATE_STORE_EXTENDS_EMBER_OBJECT: false,
      },
    },
  });

  return compatBuild(app, buildOnce);
};

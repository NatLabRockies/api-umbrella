import Application from '@ember/application';
import Resolver from 'ember-resolver';
import loadInitializers from 'ember-load-initializers';
import config from 'api-umbrella-admin-ui/config/environment';
import { importSync, macroCondition, isDevelopingApp, isTesting } from '@embroider/macros';

if (macroCondition(isDevelopingApp() || isTesting())) {
  importSync('./deprecation-workflow');
}

export default class App extends Application {
  modulePrefix = config.modulePrefix;
  podModulePrefix = config.podModulePrefix;
  Resolver = Resolver;
}

loadInitializers(App, config.modulePrefix);

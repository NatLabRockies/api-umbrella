import EmberRouter from '@embroider/router';
import config from 'api-umbrella-admin-ui/config/environment';

export default class Router extends EmberRouter {
  location = config.locationType;
  rootURL = config.rootURL;
}

Router.map(function() {
  this.route('apis', function() {
    this.route('new');
    this.route('edit', { path: '/:api_id/edit' });
  });

  this.route('api_users', function() {
    this.route('new');
    this.route('edit', { path: '/:api_user_id/edit' });
  });

  this.route('admins', function() {
    this.route('new');
    this.route('edit', { path: '/:admin_id/edit' });
  });

  this.route('api_scopes', function() {
    this.route('new');
    this.route('edit', { path: '/:api_scope_id/edit' });
  });

  this.route('admin_groups', function() {
    this.route('new');
    this.route('edit', { path: '/:admin_group_id/edit' });
  });

  this.route('config', function() {
    this.route('publish');
  });

  this.route('stats', function() {
    this.route('drilldown');
    this.route('drilldown-legacy', { path: '/drilldown/*legacyParams' });
    this.route('logs');
    this.route('logs-legacy', { path: '/logs/*legacyParams' });
    this.route('users');
    this.route('users-legacy', { path: '/users/*legacyParams' });
    this.route('map');
    this.route('map-legacy', { path: '/map/*legacyParams' });
  });

  this.route('website_backends', function() {
    this.route('new');
    this.route('edit', { path: '/:website_backend_id/edit' });
  });

  this.route('login');
  this.route('after-logout');
  this.route('error');
  this.route('not-found', { path: '/*wildcard' });
});

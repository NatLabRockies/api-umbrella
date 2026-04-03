import AuthenticatedRoute from 'api-umbrella-admin-ui/routes/authenticated-route';
import $ from 'jquery';

export default class BaseRoute extends AuthenticatedRoute {
  setupController(controller, model) {
    controller.set('model', model);

    $('ul.navbar-nav a.nav-link').removeClass('active');
    $('ul.navbar-nav li.nav-users > a.nav-link').addClass('active');
  }
}



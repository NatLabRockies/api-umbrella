import duplicableNewRoute from 'api-umbrella-admin-ui/utils/duplicable-new-route';

import Form from './form';

export default class NewRoute extends duplicableNewRoute(Form) {
  duplicateModelName = 'api-scope';
}

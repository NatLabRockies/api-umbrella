import duplicableNewRoute from 'api-umbrella-admin-ui/utils/duplicable-new-route';

import Form from './form';

export default class NewRoute extends duplicableNewRoute(Form) {
  duplicateModelName = 'api';

  newRecordAttrs() {
    return { frontendHost: location.hostname };
  }

  wrapModel(record) {
    return this.fetchModels(record);
  }

  modelFromResolved(resolved) {
    return resolved && resolved.record;
  }
}

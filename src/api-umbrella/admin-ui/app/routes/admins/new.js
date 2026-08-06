import duplicableNewRoute from 'api-umbrella-admin-ui/utils/duplicable-new-route';

import Form from './form';

export default class NewRoute extends duplicableNewRoute(Form) {
  duplicateModelName = 'admin';

  newRecordAttrs() {
    return { sendInviteEmail: true };
  }

  wrapModel(record) {
    return this.fetchModels(record);
  }

  modelFromResolved(resolved) {
    return resolved && resolved.record;
  }
}

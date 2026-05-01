import { inject as service } from '@ember/service';
import { success } from '@pnotify/core';
import { clearStoreCache } from 'api-umbrella-admin-ui/utils/uncached-model';

import Form from './form';

export default class NewRoute extends Form {
  @service store;
  @service duplicateRecord;

  queryParams = {
    duplicate_id: { refreshModel: true },
  };

  async model(params) {
    let record;
    if (params.duplicate_id) {
      record = await this.duplicateRecord.cloneFromId('admin-group', params.duplicate_id);
    } else {
      clearStoreCache(this.store);
      record = this.store.createRecord('admin-group');
    }
    return this.fetchModels(record);
  }

  afterModel(resolved) {
    const record = resolved && resolved.record;
    if (record && record._duplicatedFromName) {
      success({
        title: 'Duplicated',
        text: `Duplicated from ${record._duplicatedFromName}`,
      });
      record._duplicatedFromName = null;
    }
  }
}

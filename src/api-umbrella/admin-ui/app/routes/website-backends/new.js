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
      record = await this.duplicateRecord.cloneFromId('website-backend', params.duplicate_id);
    } else {
      clearStoreCache(this.store);
      record = this.store.createRecord('website-backend', { serverPort: 80 });
    }
    return record;
  }

  afterModel(resolved) {
    const record = resolved;
    if (record && record._duplicatedFromName) {
      success({
        title: 'Duplicated',
        text: `Duplicated from ${record._duplicatedFromName}`,
      });
      record._duplicatedFromName = null;
    }
  }
}

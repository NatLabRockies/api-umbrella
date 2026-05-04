import { inject as service } from '@ember/service';
import { success } from '@pnotify/core';
import { clearStoreCache } from 'api-umbrella-admin-ui/utils/uncached-model';

// Returns a route class that adds support for cloning a source record
// when `duplicate_id` is present in the query string. Each new-route in
// the admin UI extends `duplicableNewRoute(Form)` instead of `Form`
// directly, so this class sits between Form and the resource's NewRoute.
//
// Subclasses must declare `duplicateModelName` (the Ember Data model
// name). They may override:
//   - `newRecordAttrs()` to provide createRecord defaults on the
//     non-duplicate path (default: `{}`).
//   - `wrapModel(record)` to wrap the resolved record in a hash via
//     `this.fetchModels(record)` for resources whose form route loads
//     auxiliary data alongside the record (default: identity).
//   - `modelFromResolved(resolved)` to extract the record from the hash
//     in `afterModel` (default: identity, matching `wrapModel: identity`).
export default function duplicableNewRoute(SuperClass) {
  return class DuplicableNewRoute extends SuperClass {
    @service store;
    @service duplicateRecord;

    queryParams = {
      duplicate_id: { refreshModel: true },
    };

    duplicateModelName = null;

    newRecordAttrs() {
      return {};
    }

    wrapModel(record) {
      return record;
    }

    modelFromResolved(resolved) {
      return resolved;
    }

    async model(params) {
      let record;
      if (params.duplicate_id) {
        record = await this.duplicateRecord.cloneFromId(this.duplicateModelName, params.duplicate_id);
      } else {
        clearStoreCache(this.store);
        record = this.store.createRecord(this.duplicateModelName, this.newRecordAttrs());
      }
      return this.wrapModel(record);
    }

    afterModel(resolved) {
      const record = this.modelFromResolved(resolved);
      if (record && record._duplicatedFromName) {
        success({
          title: 'Duplicated',
          text: `Duplicated from ${record._duplicatedFromName}`,
        });
        record._duplicatedFromName = null;
      }
    }
  };
}

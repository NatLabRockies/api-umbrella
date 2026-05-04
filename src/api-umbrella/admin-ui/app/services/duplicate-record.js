import Service, { inject as service } from '@ember/service';
import cloneDeep from 'lodash-es/cloneDeep';

const UNIVERSAL_EXCLUDE = ['id', 'createdAt', 'updatedAt', 'creator', 'updater'];

export default class DuplicateRecordService extends Service {
  @service store;

  async cloneFromId(modelName, sourceId) {
    const source = await this.store.findRecord(modelName, sourceId, { reload: true });
    const clone = this._cloneRecord(modelName, source);
    clone._duplicatedFromName = source.name || source.email || 'record';
    return clone;
  }

  _cloneRecord(modelName, source) {
    const modelClass = this.store.modelFor(modelName);
    const exclude = new Set([
      ...UNIVERSAL_EXCLUDE,
      ...(modelClass.duplicateExclude || []),
    ]);

    const attrs = {};

    modelClass.eachAttribute((name) => {
      if(exclude.has(name)) {
        return;
      }
      const value = source.get(name);
      attrs[name] = this._isPlainStructure(value) ? cloneDeep(value) : value;
    });

    modelClass.eachRelationship((name, descriptor) => {
      if(exclude.has(name)) {
        return;
      }
      const related = source.get(name);
      if(descriptor.kind === 'belongsTo') {
        attrs[name] = related ? this._cloneRecord(descriptor.type, related) : null;
      } else if(descriptor.kind === 'hasMany') {
        attrs[name] = (related || []).map((child) => this._cloneRecord(descriptor.type, child));
      }
    });

    return this.store.createRecord(modelName, attrs);
  }

  _isPlainStructure(value) {
    if(value === null || value === undefined) {
      return false;
    }
    if(Array.isArray(value)) {
      return true;
    }
    return typeof value === 'object' && value.constructor === Object;
  }
}

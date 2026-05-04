import Model, { attr } from '@ember-data/model';
import { t } from 'api-umbrella-admin-ui/utils/i18n';
import { buildValidations, validator } from 'ember-cp-validations';

const Validations = buildValidations({
  name: validator('presence', {
    presence: true,
    description: t('Name'),
  }),
  host: [
    validator('presence', {
      presence: true,
      description: t('Host'),
    }),
    validator('format', {
      regex: CommonValidations.host_format_with_wildcard,
      description: t('Host'),
      message: t('must be in the format of "example.com"'),
    }),
  ],
  pathPrefix: [
    validator('presence', {
      presence: true,
      description: t('Path Prefix'),
    }),
    validator('format', {
      regex: CommonValidations.url_prefix_format,
      description: t('Path Prefix'),
      message: t('must start with "/"'),
    }),
  ],
});

class ApiScope extends Model.extend(Validations) {
  static urlRoot = '/api-umbrella/v1/api_scopes';
  static singlePayloadKey = 'api_scope';
  static arrayPayloadKey = 'data';
  static duplicateExclude = ['pathPrefix'];

  @attr()
  name;

  @attr()
  host;

  @attr()
  pathPrefix;

  @attr()
  adminGroups;

  @attr()
  createdAt;

  @attr()
  updatedAt;

  @attr()
  creator;

  @attr()
  updater;

  get displayName() {
    return this.name + ' - ' + this.host + this.pathPrefix;
  }
}

export default ApiScope;

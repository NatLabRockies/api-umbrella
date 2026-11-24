import Model, { attr, belongsTo, hasMany } from '@ember-data/model';
import { t } from 'api-umbrella-admin-ui/utils/i18n';
import classic from 'ember-classic-decorator';
import { buildValidations, validator } from 'ember-cp-validations';

const Validations = buildValidations({
  name: validator('presence', {
    presence: true,
    description: t('Name'),
  }),
  frontendHost: [
    validator('presence', {
      presence: true,
      description: t('Frontend Host'),
    }),
    validator('format', {
      regex: CommonValidations.host_format_with_wildcard,
      description: t('Frontend Host'),
      message: t('must be in the format of "example.com"'),
    }),
  ],
  backendHost: [
    validator('presence', {
      presence: true,
      description: t('Frontend Host'),
      disabled: () => {
        return (this.model.frontendHost && this.model.frontendHost[0] === '*');
      },
    }),
    validator('format', {
      regex: CommonValidations.host_format_with_wildcard,
      description: t('Backend Host'),
      message: t('must be in the format of "example.com"'),
      disabled: () => {
        return !this.model.backendHost;
      },
    }),
  ],
});

@classic
class Api extends Model.extend(Validations) {
  static urlRoot = '/api-umbrella/v1/apis';
  static singlePayloadKey = 'api';
  static arrayPayloadKey = 'data';

  @attr()
  name;

  @attr('string', { defaultValue: 'http' })
  backendProtocol;

  @attr()
  frontendHost;

  @attr()
  backendHost;

  @attr('string', { defaultValue: 'least_conn' })
  balanceAlgorithm;

  @attr()
  createdAt;

  @attr()
  updatedAt;

  @attr()
  creator;

  @attr()
  updater;

  @attr()
  organizationName;

  @attr()
  statusDescription;

  @attr()
  rootApiScope;

  @attr()
  apiScopes;

  @attr()
  adminGroups;

  @hasMany('api/server', { async: false, inverse: null })
  servers;

  @hasMany('api/url-match', { async: false, inverse: null })
  urlMatches;

  @belongsTo('api/settings', { async: false, inverse: null })
  settings;

  @hasMany('api/sub-settings', { async: false, inverse: null })
  subSettings;

  @hasMany('api/rewrites', { async: false, inverse: null })
  rewrites;

  init() {
    super.init(...arguments);

    this.setDefaults();
  }

  setDefaults() {
    if(!this.settings) {
      this.set('settings', this.store.createRecord('api/settings'));
    }

    // This can go away once we move from Ember Data's classic model layer
    // to schema records/WarpDrive. We'd need to upgrade to
    // ember data 5.x to do that kind of refactor.
    this.subSettings.forEach((subSetting) => {
      // Accessing the relationship is enough to materialize and fire init.
      // eslint-disable-next-line no-unused-expressions
      subSetting.settings;
    });
  }

  get exampleIncomingUrlRoot() {
    return 'https://' + (this.frontendHost || '');
  }

  get exampleOutgoingUrlRoot() {
    return this.backendProtocol + '://' + (this.backendHost || this.frontendHost || '');
  }
}

export default Api;

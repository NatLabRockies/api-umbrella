import { computed } from '@ember/object';
import Model, { attr, belongsTo } from '@ember-data/model';
import { t } from 'api-umbrella-admin-ui/utils/i18n';
import classic from 'ember-classic-decorator';
import { buildValidations, validator } from 'ember-cp-validations';
import compact from 'lodash-es/compact';

const Validations = buildValidations({
  firstName: validator('presence', {
    presence: true,
    description: t('First Name'),
  }),
  lastName: validator('presence', {
    presence: true,
    description: t('Last Name'),
  }),
  email: validator('presence', {
    presence: true,
    description: t('Email'),
  }),
});

@classic
class ApiUser extends Model.extend(Validations) {
  static urlRoot = '/api-umbrella/v1/users';
  static singlePayloadKey = 'user';
  static arrayPayloadKey = 'data';
  static duplicateExclude = ['apiKey', 'apiKeyHidesAt', 'apiKeyPreview', 'email', 'emailVerified', 'termsAndConditions', 'sendWelcomeEmail'];

  @attr()
  apiKey;

  @attr()
  apiKeyHidesAt;

  @attr()
  apiKeyPreview;

  @attr()
  firstName;

  @attr()
  lastName;

  @attr()
  email;

  @attr()
  emailVerified;

  @attr()
  website;

  @attr()
  useDescription;

  @attr()
  registrationSource;

  @attr()
  termsAndConditions;

  @attr()
  sendWelcomeEmail;

  @attr('boolean')
  throttleByIp;

  @attr()
  roles;

  @attr('boolean')
  enabled;

  @attr()
  createdAt;

  @attr()
  updatedAt;

  @attr()
  creator;

  @attr()
  updater;

  @attr()
  registrationIp;

  @attr()
  registrationUserAgent;

  @attr()
  registrationReferer;

  @attr()
  registrationOrigin;

  @attr()
  metadataYamlString;

  @belongsTo('api/settings', { async: false, inverse: null })
  settings;

  init() {
    super.init(...arguments);

    this.setDefaults();
  }

  setDefaults() {
    if(this.throttleByIp === undefined) {
      this.set('throttleByIp', false);
    }

    if(this.enabled === undefined) {
      this.set('enabled', true);
    }

    if(!this.settings) {
      this.set('settings', this.store.createRecord('api/settings'));
    }

    if(!this.registrationSource && this.isNew) {
      this.set('registrationSource', 'web_admin');
    }
  }

  @computed('roles')
  get rolesString() {
    let rolesString = '';
    if(this.roles) {
      rolesString = this.roles.join(',');
    }
    return rolesString;
  }

  set rolesString(value) {
    let roles = compact(value.split(','));
    if(roles.length === 0) { roles = null; }
    this.set('roles', roles);
  }
}

export default ApiUser;

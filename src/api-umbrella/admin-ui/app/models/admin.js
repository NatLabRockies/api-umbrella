import Model, { attr } from '@ember-data/model';
import usernameLabel from 'api-umbrella-admin-ui/utils/username-label'
import { buildValidations, validator } from 'ember-cp-validations';

const Validations = buildValidations({
  username: validator('presence', {
    presence: true,
    description: usernameLabel(),
  }),
});

class Admin extends Model.extend(Validations) {
  static urlRoot = '/api-umbrella/v1/admins';
  static singlePayloadKey = 'admin';
  static arrayPayloadKey = 'data';
  static duplicateExclude = ['username', 'email'];

  @attr()
  username;

  @attr()
  password;

  @attr()
  passwordConfirmation;

  @attr()
  currentPassword;

  @attr()
  email;

  @attr('boolean')
  sendInviteEmail;

  @attr()
  name;

  @attr()
  notes;

  @attr()
  superuser;

  @attr({ defaultValue() { return [] } })
  groupIds;

  @attr()
  signInCount;

  @attr()
  currentSignInAt;

  @attr()
  lastSignInAt;

  @attr()
  currentSignInIp;

  @attr()
  lastSignInIp;

  @attr()
  currentSignInProvider;

  @attr()
  lastSignInProvider;

  @attr()
  authenticationToken;

  @attr()
  createdAt;

  @attr()
  updatedAt;

  @attr()
  creator;

  @attr()
  updater;
}

export default Admin;

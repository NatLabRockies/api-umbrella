// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { reads } from '@ember/object/computed';
import { inject } from '@ember/service';
import { tagName } from '@ember-decorators/component';
// eslint-disable-next-line ember/no-mixins
import Save from 'api-umbrella-admin-ui/mixins/save';
import { sprintf, t } from 'api-umbrella-admin-ui/utils/i18n';
import usernameLabel from 'api-umbrella-admin-ui/utils/username-label';
import classic from 'ember-classic-decorator';
import escape from 'lodash-es/escape';

@classic
@tagName("")
export default class RecordForm extends Component.extend(Save) {
  @inject()
  session;

  @reads('session.data.authenticated.admin')
  currentAdmin;

  @computed('currentAdmin.permissions.admin_manage')
  get isDisabled() {
    return !this.currentAdmin.permissions.admin_manage;
  }

  @computed('currentAdmin.id', 'model.id')
  get isOwnProfile() {
    return this.currentAdmin?.id && this.model?.id && this.currentAdmin.id === this.model.id;
  }

  get usernameLabel() {
    return usernameLabel();
  }

  @action
  submitForm(event) {
    event.preventDefault();
    this.saveRecord({
      element: event.target,
      transitionToRoute: 'admins',
      message: sprintf(t('Successfully saved the admin "%s"'), escape(this.model.username)),
    });
  }

  @action
  delete() {
    this.destroyRecord({
      prompt: sprintf(t('Are you sure you want to delete the admin "%s"?'), escape(this.model.username)),
      transitionToRoute: 'admins',
      message: sprintf(t('Successfully deleted the admin "%s"'), escape(this.model.username)),
    });
  }
}

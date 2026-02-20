// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { reads } from '@ember/object/computed';
import { inject } from '@ember/service';
// eslint-disable-next-line ember/no-mixins
import Save from 'api-umbrella-admin-ui/mixins/save';
import { t } from 'api-umbrella-admin-ui/utils/i18n';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import escape from 'lodash-es/escape';

@classic
export default class RecordForm extends Component.extend(Save) {
  @inject('session')
  session;

  throttleByIpOptions = [
    { id: false, name: 'Rate limit by API key' },
    { id: true, name: 'Rate limit by IP address' },
  ];

  enabledOptions = [
    { id: true, name: 'Enabled' },
    { id: false, name: 'Disabled' },
  ];

  @reads('session.data.authenticated.admin')
  currentAdmin;

  @computed('currentAdmin.permissions.user_manage')
  get isDisabled() {
    return !this.currentAdmin.permissions.user_manage;
  }

  @action
  apiKeyRevealToggle() {
    let $key = $(this.element).find('.api-key');
    let $toggle = $(this.element).find('.api-key-reveal-toggle');

    if($key.data('revealed') === 'true') {
      $key.text($key.data('api-key-preview'));
      $key.data('revealed', 'false');
      $toggle.text(t('(reveal)'));
    } else {
      $key.text($key.data('api-key'));
      $key.data('revealed', 'true');
      $toggle.text(t('(hide)'));
    }
  }

  @action
  submitForm(event) {
    event.preventDefault();

    const currentAdmin = this.session.data.authenticated.admin;
    if(!currentAdmin.permissions.user_manage) {
      console.info('No permissions to manage users');
      return;
    }

    const isNew = this.model.get('isNew');
    this.saveRecord({
      element: event.target,
      transitionToRoute: 'api_users',
      message(model) {
        let message = '<p>Successfully saved the user "' + escape(model.get('email')) + '"</p>';
        if(isNew && model.get('apiKey')) {
          message += '<p style="font-size: 18px;"><strong>API Key:</strong> <code>' + escape(model.get('apiKey')) + '</code></p>';
          message += '<p><strong>Note:</strong> This API key will not be displayed again, so make note of it if needed.</p>';
        }

        return message;
      },
    });
  }
}

// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { service } from '@ember/service';
import LoadingButton from 'api-umbrella-admin-ui/utils/loading-button';
import bootbox from 'bootbox';
import Diff from 'diff';
import classic from 'ember-classic-decorator';
import $ from 'jquery';

@classic
export default class PublishForm extends Component {
  tagName = '';

  @service pendingFlashMessages;

  @action
  didInsert(element) {
    this.publishButton = element.querySelector('.publish-button');
    this.$toggleCheckboxesLink = $('#toggle_checkboxes');
    $('#publish_form').on('change', ':checkbox', this.onCheckboxChange.bind(this));

    let $checkboxes = $('#publish_form :checkbox');
    if($checkboxes.length === 1) {
      $checkboxes.prop('checked', true);
    }

    this.onCheckboxChange();

    $(element).find('.diff-active-yaml').each(function() {
      let activeYaml = $(this).text();
      let pendingYaml = $(this).siblings('.diff-pending-yaml').text();

      let diff = Diff.diffWords(activeYaml, pendingYaml);

      let fragment = document.createDocumentFragment();
      for(let i = 0; i < diff.length; i++) {
        if(diff[i].added && diff[i + 1] && diff[i + 1].removed) {
          let swap = diff[i];
          diff[i] = diff[i + 1];
          diff[i + 1] = swap;
        }

        let node;
        if(diff[i].removed) {
          node = document.createElement('del');
          node.appendChild(document.createTextNode(diff[i].value));
        } else if(diff[i].added) {
          node = document.createElement('ins');
          node.appendChild(document.createTextNode(diff[i].value));
        } else {
          node = document.createTextNode(diff[i].value);
        }

        fragment.appendChild(node);
      }

      let diffOutput = $(this).siblings('.config-diff');
      diffOutput.html(fragment);
    });
  }

  onCheckboxChange() {
    let $unchecked = $('#publish_form :checkbox:not(:checked)');
    if($unchecked.length > 0) {
      this.$toggleCheckboxesLink.text(this.$toggleCheckboxesLink.data('check-all'));
    } else {
      this.$toggleCheckboxesLink.text(this.$toggleCheckboxesLink.data('uncheck-all'));
    }

    if(this.publishButton) {
      let $checked = $('#publish_form :checkbox:checked');
      if($checked.length > 0) {
        this.publishButton.disabled = false;
      } else {
        this.publishButton.disabled = true;
      }
    }
  }

  @computed(
    'model.config.apis.{new.@each,modified.@each,deleted.@each}',
    'model.config.website_backends.{new.@each,modified.@each,deleted.@each}',
  )
  get hasChanges() {
    let newApis = this.model.config.apis.new;
    let modifiedApis = this.model.config.apis.modified;
    let deletedApis = this.model.config.apis.deleted;
    let newWebsiteBackends = this.model.config.website_backends.new;
    let modifiedWebsiteBackends = this.model.config.website_backends.modified;
    let deletedWebsiteBackends = this.model.config.website_backends.deleted;

    if(newApis.length > 0 || modifiedApis.length > 0 || deletedApis.length > 0 || newWebsiteBackends.length > 0 || modifiedWebsiteBackends.length > 0 || deletedWebsiteBackends.length > 0) {
      return true;
    } else {
      return false;
    }
  }

  @action
  toggleAllCheckboxes() {
    let $checkboxes = $('#publish_form :checkbox');
    let $unchecked = $('#publish_form :checkbox').not(':checked');

    if($unchecked.length > 0) {
      $checkboxes.prop('checked', true);
    } else {
      $checkboxes.prop('checked', false);
    }

    this.onCheckboxChange();
  }

  @action
  publish() {
    let form = $('#publish_form');

    LoadingButton.loading(this.publishButton);

    $.ajax({
      url: '/api-umbrella/v1/config/publish',
      type: 'POST',
      data: form.serialize(),
    }).then(() => {
      LoadingButton.reset(this.publishButton);

      this.pendingFlashMessages.add({
        type: 'success',
        title: 'Published',
        message: 'Successfully published the configuration<br>Changes should be live in a few seconds...',
      });

      this.refreshCurrentRouteController();
    }, (response) => {
      let message = '<h3>Error</h3>';
      try {
        let errors = response.responseJSON.errors;
        for(const prop in errors) {
          message += prop + ': ' + errors[prop].join(', ') + '<br>';
        }
      } catch(e) {
        message = 'An unexpected error occurred: ' + response.responseText;
      }

      LoadingButton.reset(this.publishButton);
      // eslint-disable-next-line no-console
      console.error(message);
      bootbox.alert(message);
    });
  }
}

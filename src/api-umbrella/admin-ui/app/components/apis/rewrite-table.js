// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action } from '@ember/object';
import { inject as service } from '@ember/service';
import { tagName } from '@ember-decorators/component';
import bootbox from 'bootbox';
import classic from 'ember-classic-decorator';
import without from 'lodash-es/without';

@classic
@tagName("")
export default class RewriteTable extends Component {
  @service store;

  openModal = false;

  @action
  add() {
    this.set('rewriteModel', this.store.createRecord('api/rewrite'));
    this.set('openModal', true);
  }

  @action
  edit(rewrite) {
    this.set('rewriteModel', rewrite);
    this.set('openModal', true);
  }

  @action
  remove(rewrite) {
    bootbox.confirm('Are you sure you want to remove this rewrite?', (response) => {
      if(response) {
        let collection = without(this.model.rewrites, rewrite);
        this.model.set('rewrites', collection);
      }
    });
  }
}

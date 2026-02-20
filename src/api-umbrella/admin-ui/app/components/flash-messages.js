import Component from '@glimmer/component';
import { service } from '@ember/service';

export default class FlashMessages extends Component {
  @service currentFlashMessages;
}

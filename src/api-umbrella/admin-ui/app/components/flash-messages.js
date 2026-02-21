import { service } from '@ember/service';
import Component from '@glimmer/component';

export default class FlashMessages extends Component {
  @service currentFlashMessages;
}

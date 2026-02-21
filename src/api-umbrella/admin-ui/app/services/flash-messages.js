import { A } from '@ember/array';
import Service from '@ember/service';

export default class FlashMessagesService extends Service {
  items = A([]);

  add(item) {
    this.items.pushObject(item);
  }

  empty() {
    this.items.clear();
  }
}

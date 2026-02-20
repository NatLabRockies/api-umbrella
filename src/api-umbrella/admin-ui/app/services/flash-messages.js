import Service from '@ember/service';
import { A } from '@ember/array';
import ArrayProxy from '@ember/array/proxy';

export default class FlashMessagesService extends Service {
  items = A([]);

  add(item) {
    this.items.pushObject(item);
  }

  empty() {
    this.items.clear();
  }
}

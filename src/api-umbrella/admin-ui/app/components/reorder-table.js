import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import {DragDropManager} from '@dnd-kit/dom';
import {RestrictToVerticalAxis} from '@dnd-kit/abstract/modifiers';
import {Sortable} from '@dnd-kit/dom/sortable';

export default class ReorderTable extends Component {
  @tracked isReordering = false;

  constructor(owner, args) {
    super(...arguments);

    // this.addObserver('args.collection', this, () => {
    //   console.info('COLLECTION CHANGES');
    // });
  }

  get isReorderable() {
    console.info('isReorderable');
    const length = this.args.collection.length;
    return (length > 1);
  }

  @action
  toggleReordering() {
    this.isReordering = !this.isReordering;
    console.info('toggleReordering');
    const length = this.args.collection.length;
    console.info('length: ', length);


    const observer = new MutationObserver((mutationList) => {
      console.info('MUTATION: ', mutationList);
      console.info('MUTATION: ', mutationList[0]);
    });
    observer.observe(document.querySelector(`#${this.args.tableId} tbody`), {
      childList: true,
    });

    this.makeSortable();
  }

  makeSortable() {
    const container = document.getElementById(this.args.tableId);

    if (this.isReordering) {
      container.classList.add('reorder-active');
    } else {
      container.classList.remove('reorder-active');
    }

    const manager = new DragDropManager({
      modifiers: (defaults) => [...defaults, RestrictToVerticalAxis],
    });
    const tableRowEls = container.querySelectorAll('tbody tr');
    for (const [index, tableRowEl] of tableRowEls.entries()) {
      console.info(tableRowEl);
      const sortable = new Sortable({
        id: tableRowEl.dataset.guid,
        index,
        element: tableRowEl,
        handle: tableRowEl.querySelector('.reorder-handle'),
      }, manager);
    }
  }
}

import {RestrictToVerticalAxis} from '@dnd-kit/abstract/modifiers';
import {DragDropManager} from '@dnd-kit/dom';
import {isSortable,Sortable} from '@dnd-kit/dom/sortable';
import { action } from '@ember/object';
import { guidFor } from '@ember/object/internals';
import { schedule } from '@ember/runloop';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';

export default class ReorderTable extends Component {
  @tracked isReordering = false;

  constructor() {
    super(...arguments);
    this.setupDomSorting();
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.destroyDomSorting();
  }

  get isReorderable() {
    const length = this.args.collection.length;
    this.handleCollectionChange();
    return (length > 1);
  }

  get container() {
    const container = document.getElementById(this.args.tableId);
    return container;
  }

  handleCollectionChange() {
    schedule('afterRender', this, function() {
      this.setupDomSorting();
    });
  }

  @action
  toggleReordering() {
    this.isReordering = !this.isReordering;
    this.setupDomSorting();
  }

  setupDomSorting() {
    this.destroyDomSorting();

    if(!this.container) {
      console.error('tableId doesn not exist: ', this.args.tableId);
      return;
    }

    if(this.isReordering) {
      this.container.classList.add('reorder-active');
    } else {
      this.container.classList.remove('reorder-active');
    }

    this.manager = new DragDropManager({
      modifiers: (defaults) => [...defaults, RestrictToVerticalAxis],
    });

    this.sortables = [];
    const tableRowEls = this.container.querySelectorAll('tbody tr');
    for(const [index, tableRowEl] of tableRowEls.entries()) {
      this.sortables.push(new Sortable({
        id: tableRowEl.dataset.guid,
        index,
        element: tableRowEl,
        handle: tableRowEl.querySelector('.reorder-handle'),
      }, this.manager));
    }

    this.manager.monitor.addEventListener('dragend', this.handleDragEnd.bind(this));
  }

  destroyDomSorting() {
    if(this.manager) {
      this.manager.destroy();
    }
  }

  handleDragEnd(event) {
    if(event.canceled || !isSortable(event.operation.source)) {
      return;
    }

    const indexes = {};
    for(const sortable of this.sortables) {
      indexes[sortable.id] = sortable.index;
    }

    this.updateCollectionSortOrders(indexes);
  }

  updateCollectionSortOrders(indexes) {
    for(const record of this.args.collection) {
      const index = indexes[guidFor(record)];
      record.set('sortOrder', index + 1);
    }
  }
}

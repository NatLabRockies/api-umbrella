import { action } from '@ember/object';
import {DragDropManager} from '@dnd-kit/dom';
import {RestrictToVerticalAxis} from '@dnd-kit/abstract/modifiers';
import {Sortable as DndSortable} from '@dnd-kit/dom/sortable';
import { guidFor } from '@ember/object/internals';
import { tracked } from '@glimmer/tracking';
import { t } from 'api-umbrella-admin-ui/utils/i18n';
import sortable from 'html5sortable/dist/html5sortable.es';

export default class Sortable {
  @tracked sortableCollection;

  constructor(sortableCollection) {
    console.info('constructor!');
    this.sortableCollection = sortableCollection;
  }

  get isReorderable() {
    console.info('isReorderable');
    const length = this.sortableCollection.length;
    return (length > 1);
  }

  updateSortOrder(indexes) {
    this.sortableCollection.forEach(function(record) {
      const index = indexes[guidFor(record)];
      record.set('sortOrder', index + 1);
    });
  }

  @action
  reorderCollection(containerId) {
    const container = document.getElementById(containerId);
    const buttonText = container.querySelector('.reorder-button-text');

    if(container.classList.contains('reorder-active')) {
      buttonText.innerText = buttonText.dataset.originalText;
      container.classList.remove('reorder-active');
    } else {
      buttonText.dataset.originalText = buttonText.innerText;
      buttonText.innerText = t('Done');
      container.classList.add('reorder-active');
    }

    const manager = new DragDropManager({
      modifiers: (defaults) => [...defaults, RestrictToVerticalAxis],
    });
    const tableRowEls = container.querySelectorAll('tbody tr');
    for (const [index, tableRowEl] of tableRowEls.entries()) {
      console.info(tableRowEl);
      const sortable = new DndSortable({
        id: tableRowEl.dataset.guid,
        index,
        element: tableRowEl,
        handle: tableRowEl.querySelector('.reorder-handle'),
      }, manager);
    }

    /*
    const tbody = container.querySelector('tbody');
    sortable(tbody, {
      items: 'tr',
      handle: '.reorder-handle',
      forcePlaceholderSize: true,
      placeholderClass: 'reorder-placeholder',
    });
    tbody.addEventListener('sortstart', () => {
      console.info('sortstart: ', arguments);
    });
    tbody.addEventListener('sortstop', () => {
      console.info('sortstop: ', arguments);
    });
    tbody.addEventListener('sortenter', () => {
      console.info('sortenter: ', arguments);
    });
    tbody.addEventListener('sortleave', () => {
      console.info('sortleave: ', arguments);
    });
    tbody.addEventListener('sortupdate', () => {
      console.info('sortupdate: ', arguments);
      const indexes = {};
      const rows = tbody.querySelectorAll('tr');
      for(let i = 0; i < rows.length; i++) {
        const row = rows[i];
        indexes[row.dataset.guid] = i;
      }

      this.updateSortOrder(indexes);
    });
    */
  }
}

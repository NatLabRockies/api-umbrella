// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { inject } from '@ember/service';
import { observes } from '@ember-decorators/object';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import clone from 'lodash-es/clone';
import escape from 'lodash-es/escape';
import numeral from 'numeral';

@classic
export default class ResultsTable extends Component {
  tagName = '';

  @inject()
  session;

  @action
  didInsert(element) {
    this.table = $(element).find('table').DataTable({
      searching: false,
      order: [[1, 'desc']],
      data: this.results,
      columns: [
        {
          data: 'path',
          title: 'Path',
          defaultContent: '-',
          render: (name, type, data) => {
            if(type === 'display' && name && name !== '-') {
              if(data.terminal) {
                return '<i class="far fa-file fa-fw me-1"></i>' + escape(name);
              } else {
                let params = clone(this.presentQueryParamValues);
                params.prefix = data.descendent_prefix;
                let link = '#/stats/drilldown?' + $.param(params);

                return '<a href="' + link + '"><i class="far fa-folder fa-fw me-1"></i>' + escape(name) + '</a>';
              }
            }

            return name;
          },
        },
        {
          data: 'hits',
          title: 'Hits',
          defaultContent: '-',
          render(number, type) {
            if(type === 'display' && number && number !== '-') {
              return numeral(number).format('0,0');
            }

            return number;
          },
        },
      ],
    });
  }

  // eslint-disable-next-line ember/no-observers
  @observes('results')
  refreshData() {
    if(this.table) {
      this.table.clear();
      this.table.rows.add(this.results);
      this.table.draw();
    }
  }

  @computed('backendQueryParamValues', 'session.data.authenticated.api_key')
  get downloadUrl() {
    return '/api-umbrella/v1/analytics/drilldown.csv?api_key=' + this.session.data.authenticated.api_key + '&' + $.param(this.backendQueryParamValues);
  }
}

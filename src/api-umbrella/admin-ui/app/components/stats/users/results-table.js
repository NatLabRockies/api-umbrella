// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { inject } from '@ember/service';
import { observes } from '@ember-decorators/object';
import DataTablesHelpers from 'api-umbrella-admin-ui/utils/data-tables-helpers';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import clone from 'lodash-es/clone';
import escape from 'lodash-es/escape';
import extend from 'lodash-es/extend';
import numeral from 'numeral';

@classic
export default class ResultsTable extends Component {
  tagName = '';

  @inject('session')
  session;

  @action
  didInsert(element) {
    this.table = $(element).find('table').DataTable({
      searching: false,
      serverSide: true,
      ajax: {
        url: '/admin/stats/users.json',
        data: (data) => {
          return extend({}, data, this.backendQueryParamValues);
        },
      },
      order: [[4, 'desc']],
      columns: [
        {
          data: 'email',
          title: 'Email',
          defaultContent: '-',
          render: (email, type, data) => {
            if(type === 'display' && email && email !== '-') {
              let params = clone(this.presentQueryParamValues);
              params.search = 'user_id:"' + data.id + '"';
              let link = '#/stats/logs?' + $.param(params);

              return '<a href="' + link + '">' + escape(email) + '</a>';
            }

            return email;
          },
        },
        {
          data: 'first_name',
          title: 'First Name',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'last_name',
          title: 'Last Name',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'created_at',
          type: 'date',
          title: 'Signed Up',
          defaultContent: '-',
          render: DataTablesHelpers.renderTime(this.session.data.authenticated.analytics_timezone),
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
        {
          data: 'last_request_at',
          type: 'date',
          title: 'Last Request',
          defaultContent: '-',
          render: DataTablesHelpers.renderTime(this.session.data.authenticated.analytics_timezone),
        },
        {
          data: 'use_description',
          title: 'Use Description',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
      ],
    });
  }

  // eslint-disable-next-line ember/no-observers
  @observes('backendQueryParamValues')
  refreshData() {
    if(this.table) {
      this.table.draw();
    }
  }

  @computed('backendQueryParamValues')
  get downloadUrl() {
    return '/admin/stats/users.csv?' + $.param(this.backendQueryParamValues);
  }
}

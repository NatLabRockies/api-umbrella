// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { inject } from '@ember/service';
import DataTablesHelpers from 'api-umbrella-admin-ui/utils/data-tables-helpers';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import escape from 'lodash-es/escape';

@classic
export default class IndexTable extends Component {
  tagName = '';

  @inject()
  session;

  @action
  didInsert(element) {
    const dataTable = $(element).find('table').DataTable({
      serverSide: true,
      ajax: '/api-umbrella/v1/users.json',
      pageLength: 50,
      order: [[4, 'desc']],
      columns: [
        {
          data: 'email',
          title: 'E-mail',
          defaultContent: '-',
          render: (email, type, data) => {
            if(type === 'display' && email && email !== '-') {
              let link = '#/api_users/' + data.id + '/edit';
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
          data: 'use_description',
          title: 'Purpose',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'created_at',
          type: 'date',
          title: 'Created',
          defaultContent: '-',
          render: DataTablesHelpers.renderTime(this.session.data.authenticated.analytics_timezone),
        },
        {
          data: 'registration_source',
          title: 'Registration Source',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'api_key_preview',
          title: 'API Key',
          defaultContent: '-',
          orderable: false,
          render: DataTablesHelpers.renderEscaped,
        },
      ],
    });

    dataTable.on('draw.dt', () => {
      let params = dataTable.ajax.params();
      delete params.start;
      delete params.length;
      this.set('csvQueryParams', params);
    });
  }

  @computed('csvQueryParams', 'session.data.authenticated.api_key')
  get downloadUrl() {
    const params = $.param({
      ...(this.csvQueryParams || {}),
      api_key: this.session.data.authenticated.api_key,
    });

    return `/api-umbrella/v1/users.csv?${params}`;
  }
}

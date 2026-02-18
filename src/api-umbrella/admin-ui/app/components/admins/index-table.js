// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { inject } from '@ember/service';
import DataTablesHelpers from 'api-umbrella-admin-ui/utils/data-tables-helpers';
import { t } from 'api-umbrella-admin-ui/utils/i18n';
import usernameLabel from 'api-umbrella-admin-ui/utils/username-label';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import escape from 'lodash-es/escape';

@classic
export default class IndexTable extends Component {
  tagName = '';

  @inject('session')
  session;

  @action
  didInsert(element) {
    const dataTable = $(element).find('table').DataTable({
      serverSide: true,
      ajax: '/api-umbrella/v1/admins.json',
      pageLength: 50,
      order: [[0, 'asc']],
      columns: [
        {
          data: 'username',
          name: 'Username',
          title: usernameLabel(),
          defaultContent: '-',
          render: (username, type, data) => {
            if(type === 'display' && username && username !== '-') {
              let link = '#/admins/' + data.id + '/edit';
              return '<a href="' + link + '">' + escape(username) + '</a>';
            }

            return username;
          },
        },
        {
          data: 'groups',
          name: 'Groups',
          title: t('Groups'),
          orderable: false,
          render: (value, type, row) => {
            if(row.superuser === true) {
              // For superusers, append this to the list of groups for display
              // purposes (even though it isn't really a group and can't be
              // linked, like the other admin groups).
              value.push({
                name: t('Superuser'),
              });
            }

            return DataTablesHelpers.renderLinkedList({
              editLink: '#/admin_groups/',
              nameField: 'name',
            })(value, type);
          },
        },
        {
          data: 'current_sign_in_at',
          type: 'date',
          name: 'Last Signed In',
          title: t('Last Signed In'),
          defaultContent: '-',
          render: DataTablesHelpers.renderTime(this.session.data.authenticated.analytics_timezone),
        },
        {
          data: 'created_at',
          type: 'date',
          name: 'Created',
          title: t('Created'),
          defaultContent: '-',
          render: DataTablesHelpers.renderTime(this.session.data.authenticated.analytics_timezone),
        },
      ],
    });

    dataTable.on('draw.dt', () => {
      let params = dataTable.ajax.params();
      delete params.start;
      delete params.length;
      this.set('queryParams', params);
    });
  }

  @computed('queryParams', 'session.data.authenticated.api_key')
  get downloadUrl() {
    let params = this.queryParams;
    if(params) {
      params = $.param(params);
    }

    return '/api-umbrella/v1/admins.csv?api_key=' + this.session.data.authenticated.api_key + '&' + params;
  }
}

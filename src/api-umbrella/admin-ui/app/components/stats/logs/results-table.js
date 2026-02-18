// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action, computed } from '@ember/object';
import { inject } from '@ember/service';
import { observes } from '@ember-decorators/object';
import Logs from 'api-umbrella-admin-ui/models/stats/logs';
import DataTablesHelpers from 'api-umbrella-admin-ui/utils/data-tables-helpers';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import clone from 'lodash-es/clone';
import compact from 'lodash-es/compact';
import escape from 'lodash-es/escape';
import extend from 'lodash-es/extend';
import { marked } from 'marked';
import tippy from 'tippy.js'

marked.use({
  gfm: true,
  breaks: true,
});

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
        url: '/admin/stats/logs.json',
        // Use POST for this endpoint, since the URLs can be very long and
        // exceed URL length limits in IE (and apparently Capybara too).
        type: 'POST',
        data: (data) => {
          return extend({}, data, this.backendQueryParamValues);
        },
      },
      drawCallback: () => {
        $(element).find('td').each(function() {
          if(this.scrollWidth > this.offsetWidth) {
            const $cell = $(this);
            $cell.attr('data-tippy-content', $cell.text());

            tippy($cell[0], {
              interactive: true,
              theme: 'light-border forced-wide',
              arrow: true,
              delay: 200,
            });
          }
        });
      },
      order: [[0, 'desc']],
      columns: [
        {
          data: 'request_at',
          type: 'date',
          title: 'Time',
          defaultContent: '-',
          render: DataTablesHelpers.renderTime(this.session.data.authenticated.analytics_timezone),
        },
        {
          data: 'request_method',
          title: 'Method',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_host',
          title: 'Host',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_url',
          title: 'URL',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'user_email',
          title: 'User',
          defaultContent: '-',
          render: (email, type, data) => {
            if(type === 'display' && email && email !== '-') {
              let params = clone(this.presentQueryParamValues);
              params.search = compact([params.search, 'user_id:"' + data.user_id + '"']).join(' AND ');
              let link = '#/stats/logs?' + $.param(params);

              return '<a href="' + link + '">' + escape(email) + '</a>';
            }

            return email;
          },
        },
        {
          data: 'request_ip',
          title: 'IP Address',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_ip_country',
          title: 'Country',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_ip_region',
          title: 'State',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_ip_city',
          title: 'City',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_status',
          title: 'Status',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'gatekeeper_denied_code',
          title: 'Reason Denied',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_time',
          title: 'Response Time',
          defaultContent: '-',
          render(time, type) {
            if(type === 'display' && time && time !== '-') {
              return time + ' ms';
            }

            return time;
          },
        },
        {
          data: 'response_content_type',
          title: 'Content Type',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_accept_encoding',
          title: 'Accept Encoding',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_user_agent',
          title: 'User Agent',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_user_agent_family',
          title: 'User Agent Family',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_user_agent_type',
          title: 'User Agent Type',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_referer',
          title: 'Referer',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_origin',
          title: 'Origin',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_accept',
          title: 'Request Accept',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_connection',
          title: 'Request Connection',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_content_type',
          title: 'Request Content Type',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_scheme',
          title: 'URL Scheme',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_size',
          title: 'Request Size',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_age',
          title: 'Response Age',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_cache',
          title: 'Response Cache',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_cache_flags',
          title: 'Response Cache Flags',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_content_encoding',
          title: 'Response Content Encoding',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_content_length',
          title: 'Response Content Length',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_server',
          title: 'Response Server',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_size',
          title: 'Response Size',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_transfer_encoding',
          title: 'Response Transfer Encoding',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_custom1',
          title: 'Response Custom Dimension 1',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_custom2',
          title: 'Response Custom Dimension 2',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'response_custom3',
          title: 'Response Custom Dimension 3',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'user_id',
          title: 'User ID',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'api_backend_id',
          title: 'API Backend ID',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'api_backend_resolved_host',
          title: 'API Backend Resolved Host',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'api_backend_response_code_details',
          title: 'API Backend Response Code Details',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'api_backend_response_flags',
          title: 'API Backend Response Flags',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
        {
          data: 'request_id',
          title: 'Request ID',
          defaultContent: '-',
          render: DataTablesHelpers.renderEscaped,
        },
      ],
      headerCallback(thead) {
        if(!thead.classList.contains('tooltips-added')) {
          this.api().columns().every(function() {
            const tooltipContent = Logs.fieldTooltips[this.dataSrc()];

            if(tooltipContent) {
              const tooltipButtonEl = document.createElement('button');
              tooltipButtonEl.className = 'btn btn-link btn-tooltip';
              tooltipButtonEl.type = 'button';
              tooltipButtonEl.innerHTML = '<i class="fas fa-question-circle"></i><span class="sr-only">Help</span>';

              tippy(tooltipButtonEl, {
                trigger: 'click',
                interactive: true,
                theme: 'light-border',
                arrow: true,
                allowHTML: true,
                content: marked(tooltipContent),
                onTrigger(tip, event) {
                  event.stopPropagation();
                },
                onUntrigger(tip, event) {
                  event.stopPropagation();
                },
              });

              const headerEl = this.header();
              headerEl.innerHTML += '&nbsp;';
              headerEl.appendChild(tooltipButtonEl);
            }
          });

          thead.classList.add('tooltips-added');
        }

        $.fn.DataTable.defaults.headerCallback.apply(this, arguments);
      },
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
    return '/admin/stats/logs.csv?' + $.param(this.backendQueryParamValues);
  }
}

import 'daterangepicker';

// eslint-disable-next-line ember/no-classic-components
import Component from '@ember/component';
import { action } from '@ember/object';
import { inject } from '@ember/service';
import { tagName } from '@ember-decorators/component';
import { observes } from '@ember-decorators/object';
import Logs from 'api-umbrella-admin-ui/models/stats/logs';
import { t } from 'api-umbrella-admin-ui/utils/i18n';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import QueryBuilder from 'jQuery-QueryBuilder';
import forEach from 'lodash-es/forEach';
import { marked } from 'marked';
import moment from 'moment-timezone';
import tippy from 'tippy.js';

marked.use({
  gfm: true,
  breaks: true,
});

QueryBuilder.define('filter-description', function() {
  this.on('afterUpdateRuleFilter afterUpdateRuleOperator', function(e, rule) {
    let buttonEl = rule.$el[0].querySelector('button.filter-description');
    const description = e.builder.getFilterDescription(rule.filter, rule);

    if(!description) {
      buttonEl.style.display = 'none';
    } else {
      if(!buttonEl) {
        buttonEl = document.createElement('button');
        buttonEl.type = 'button';
        buttonEl.className = 'btn btn-sm btn-link border filter-description tooltip-trigger';
        buttonEl.innerHTML = '<i class="fas fa-question-circle"></i>';

        const ruleActionEl = rule.$el[0].querySelector(QueryBuilder.selectors.rule_actions);
        ruleActionEl.prepend(buttonEl);
      } else {
        buttonEl.style.display = '';
      }

      buttonEl.dataset.tippyContent = marked(description);
    }
  });
});

@classic
@tagName("")
export default class QueryForm extends Component {
  @inject('session')
  session;

  enableInterval = false;

  @action
  didInsert() {
    let rangeOptions = {};
    let rangeKeys = {};
    forEach(this.dateRanges, function(range, key) {
      rangeOptions[range.label] = [
        range.start_at,
        range.end_at,
      ];
      rangeKeys[range.label] = key;
    });
    this.set('rangeOptions', rangeOptions);
    this.set('rangeKeys', rangeKeys);

    let $dateRangePicker = $('#reportrange');
    $dateRangePicker.daterangepicker({
      ranges: rangeOptions,
      showDropdowns: true,
      minYear: 2000,
      maxYear: new Date().getFullYear() + 1,
    });
    $dateRangePicker.on('showCalendar.daterangepicker', this.handleDateRangeCalendarShow.bind(this));
    $dateRangePicker.on('hideCalendar.daterangepicker', this.handleDateRangeCalendarHide.bind(this));
    $dateRangePicker.on('apply.daterangepicker', this.handleDateRangeApply.bind(this));

    this.dateRangePicker = $dateRangePicker.data('daterangepicker');
    this.updateDateRange();

    let stringOperators = [
      'begins_with',
      'not_begins_with',
      'equal',
      'not_equal',
      'contains',
      'not_contains',
      'is_null',
      'is_not_null',
    ];

    let selectOperators = [
      'equal',
      'not_equal',
      'is_null',
      'is_not_null',
    ];

    let numberOperators = [
      'equal',
      'not_equal',
      'less',
      'less_or_equal',
      'greater',
      'greater_or_equal',
      'between',
      'is_null',
      'is_not_null',
    ];

    let $queryBuilder = $('#query_builder').queryBuilder({
      plugins: {
        'filter-description': {
          mode: 'tippy',
        },
      },
      allow_empty: true,
      allow_groups: false,
      filters: [
        {
          id: 'request_host',
          label: t('Request: URL Host'),
          description: Logs.fieldTooltips.request_host,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_path',
          label: t('Request: URL Path'),
          description: Logs.fieldTooltips.request_path,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_scheme',
          label: t('Request: URL Scheme'),
          description: Logs.fieldTooltips.request_scheme,
          type: 'string',
          operators: selectOperators,
          input: 'select',
          values: {
            'http': 'http',
            'https': 'https',
          },
        },
        {
          id: 'request_url_query',
          label: t('Request: URL Query String'),
          description: Logs.fieldTooltips.request_url_query,
          type: 'string',
          operators: stringOperators,
        },
        ...((window.apiUmbrellaConfig.opensearch.template_version < 2) ? [{
          id: 'request_url',
          label: t('Request: Full URL & Query String'),
          description: Logs.fieldTooltips.legacy_request_url,
          type: 'string',
          operators: stringOperators,
        }] : []),
        {
          id: 'request_method',
          label: t('Request: HTTP Method'),
          description: Logs.fieldTooltips.request_method,
          type: 'string',
          operators: selectOperators,
          input: 'select',
          values: {
            'get': 'GET',
            'post': 'POST',
            'put': 'PUT',
            'delete': 'DELETE',
            'head': 'HEAD',
            'patch': 'PATCH',
            'options': 'OPTIONS',
          },
        },
        {
          id: 'request_ip',
          label: t('Request: IP Address'),
          description: Logs.fieldTooltips.request_ip,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_ip_country',
          label: t('Request: IP Country'),
          description: Logs.fieldTooltips.request_ip_country,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_ip_region',
          label: t('Request: IP State/Region'),
          description: Logs.fieldTooltips.request_ip_region,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_ip_city',
          label: t('Request: IP City'),
          description: Logs.fieldTooltips.request_ip_city,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_user_agent',
          label: t('Request: User Agent'),
          description: Logs.fieldTooltips.request_user_agent,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_user_agent_family',
          label: t('Request: User Agent Family'),
          description: Logs.fieldTooltips.request_user_agent_family,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_user_agent_type',
          label: t('Request: User Agent Type'),
          description: Logs.fieldTooltips.request_user_agent_type,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_referer',
          label: t('Request: Referer'),
          description: Logs.fieldTooltips.request_referer,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_origin',
          label: t('Request: Origin'),
          description: Logs.fieldTooltips.request_origin,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_accept',
          label: t('Request: Accept'),
          description: Logs.fieldTooltips.request_accept,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_accept_encoding',
          label: t('Request: Accept Encoding'),
          description: Logs.fieldTooltips.request_accept_encoding,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_content_type',
          label: t('Request: Content Type'),
          description: Logs.fieldTooltips.request_content_type,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_connection',
          label: t('Request: Connection'),
          description: Logs.fieldTooltips.request_connection,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'request_size',
          label: t('Request: Size'),
          description: Logs.fieldTooltips.request_size,
          type: 'integer',
          operators: numberOperators,
        },
        {
          id: 'request_id',
          label: t('Request: ID'),
          description: Logs.fieldTooltips.request_id,
          type: 'string',
          operators: [
            'equal',
            'not_equal',
          ],
        },
        {
          id: 'api_key',
          label: t('User: API Key'),
          description: Logs.fieldTooltips.api_key,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'user_email',
          label: t('User: E-mail'),
          description: Logs.fieldTooltips.user_email,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'user_id',
          label: t('User: ID'),
          description: Logs.fieldTooltips.user_id,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_status',
          label: t('Response: HTTP Status Code'),
          description: Logs.fieldTooltips.response_status,
          type: 'integer',
          operators: numberOperators,
        },
        {
          id: 'gatekeeper_denied_code',
          label: t('Response: API Umbrella Denied Code'),
          description: Logs.fieldTooltips.gatekeeper_denied_code,
          type: 'string',
          operators: selectOperators,
          input: 'select',
          values: {
            'not_found': 'not_found',
            'api_key_missing': 'api_key_missing',
            'api_key_invalid': 'api_key_invalid',
            'api_key_disabled': 'api_key_disabled',
            'api_key_unverified': 'api_key_unverified',
            'api_key_unauthorized': 'api_key_unauthorized',
            'over_rate_limit': 'over_rate_limit',
            'internal_server_error': 'internal_server_error',
            'https_required': 'https_required',
          },
        },
        {
          id: 'response_age',
          label: t('Response: Age'),
          description: Logs.fieldTooltips.response_age,
          type: 'integer',
          operators: numberOperators,
        },
        {
          id: 'response_cache',
          label: t('Response: Cache'),
          description: Logs.fieldTooltips.response_cache,
          type: 'string',
          operators: selectOperators,
          input: 'select',
          values: {
            'HIT': 'HIT',
            'MISS': 'MISS',
          },
        },
        {
          id: 'response_cache_flags',
          label: t('Response: Cache Flags'),
          description: Logs.fieldTooltips.response_cache_flags,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_content_encoding',
          label: t('Response: Content Encoding'),
          description: Logs.fieldTooltips.response_content_encoding,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_content_length',
          label: t('Response: Content Length'),
          description: Logs.fieldTooltips.response_content_length,
          type: 'integer',
          operators: numberOperators,
        },
        {
          id: 'response_content_type',
          label: t('Response: Content Type'),
          description: Logs.fieldTooltips.response_content_type,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_server',
          label: t('Response: Server'),
          description: Logs.fieldTooltips.response_server,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_transfer_encoding',
          label: t('Response: Transfer Encoding'),
          description: Logs.fieldTooltips.response_transfer_encoding,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_time',
          label: t('Response: Load Time'),
          description: Logs.fieldTooltips.response_time,
          type: 'integer',
          operators: numberOperators,
        },
        {
          id: 'response_size',
          label: t('Response: Size'),
          description: Logs.fieldTooltips.response_size,
          type: 'integer',
          operators: numberOperators,
        },
        {
          id: 'response_custom1',
          label: t('Response: Custom Dimension 1'),
          description: Logs.fieldTooltips.response_custom1,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_custom2',
          label: t('Response: Custom Dimension 2'),
          description: Logs.fieldTooltips.response_custom2,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'response_custom3',
          label: t('Response: Custom Dimension 3'),
          description: Logs.fieldTooltips.response_custom3,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'api_backend_id',
          label: t('API Backend: ID'),
          description: Logs.fieldTooltips.api_backend_id,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'api_backend_resolved_host',
          label: t('API Backend: Resolved Host'),
          description: Logs.fieldTooltips.api_backend_resolved_host,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'api_backend_response_code_details',
          label: t('API Backend: Response Code Details'),
          description: Logs.fieldTooltips.api_backend_response_code_details,
          type: 'string',
          operators: stringOperators,
        },
        {
          id: 'api_backend_response_flags',
          label: t('API Backend: Response Flags'),
          description: Logs.fieldTooltips.api_backend_response_flags,
          type: 'string',
          operators: stringOperators,
        },
      ],
    });

    let query = this.query;
    let rules;
    if(query) {
      rules = JSON.parse(query);
    }

    if(rules) {
      if(rules.condition) {
        $queryBuilder.queryBuilder('setRules', rules);
      }

      this.send('toggleFilterType', 'builder');
    } else if(this.search) {
      this.send('toggleFilterType', 'advanced');
    }

    const helpTriggerLink = document.querySelector('.lucene-help-link');
    const helpContent = document.getElementById('query_syntax_help_content');
    if(helpTriggerLink && helpContent) {
      this.helpTippy = tippy(helpTriggerLink, {
        trigger: 'click',
        interactive: true,
        theme: 'light-border',
        arrow: true,
        allowHTML: true,
        content: helpContent.innerHTML,
        placement: 'bottom-start',
        maxWidth: 'none',
        // Below the sticky navigation header, since this popover can be so
        // large and cause the page to scroll.
        zIndex: 1019,
      });

    }
  }

  willDestroy() {
    if(this.helpTippy) {
      this.helpTippy.destroy();
    }
    super.willDestroy(...arguments);
  }

  // eslint-disable-next-line ember/no-observers
  @observes('query')
  updateQueryBuilderRules() {
    let query = this.query;
    let rules;
    if(query) {
      rules = JSON.parse(query);
    }

    if(rules && rules.condition) {
      $('#query_builder').queryBuilder('setRules', rules);
    } else {
      $('#query_builder').queryBuilder('reset');
    }
  }

  // eslint-disable-next-line ember/no-observers
  @observes('allQueryParamValues.start_at', 'allQueryParamValues.end_at')
  updateDateRange() {
    let start = moment(this.allQueryParamValues.start_at, 'YYYY-MM-DD');
    let end = moment(this.allQueryParamValues.end_at, 'YYYY-MM-DD');

    this.dateRangePicker.hideCalendars();
    this.dateRangePicker.setStartDate(start);
    this.dateRangePicker.setEndDate(end);
    $('#reportrange span.text').html(start.format('ll') + ' - ' + end.format('ll'));
  }

  handleDateRangeCalendarShow() {
    this.set('calendarShown', true);
  }

  handleDateRangeCalendarHide() {
    this.set('calendarShown', false);
  }

  handleDateRangeApply(event, picker) {
    // If the user selects a predefined date range (like "Last 7 Days"), then
    // don't set explicit dates in the URL query params. This allows for the
    // URLs that are bookmarked or shared to use relative dates (eg, you'll
    // always see the last 7 days regardless of when the URL was first
    // bookmarked).
    //
    // If the user selects a custom date range, then explicit dates will be set
    // in the URL (so the data is fixed in time).
    //
    // Note that if the user picks "Custom Range" and happens to select dates
    // that correspond with the one of the predefined ranges, then the
    // Bootstrap Date Picker sets the "chosenLabel" as if the user picked the
    // predefined range. To workaround this issue (so any dates picked when
    // "Custom Range" is open are treated the same), we check to see if the
    // "Custom Range" calendars are visible or not.
    let rangeOptions = this.rangeOptions;
    if(rangeOptions[picker.chosenLabel] && !this.calendarShown) {
      let rangeKeys = this.rangeKeys;
      this.setProperties({
        start_at: '',
        end_at: '',
        date_range: rangeKeys[picker.chosenLabel],
      });
    } else {
      this.setProperties({
        start_at: picker.startDate.format('YYYY-MM-DD'),
        end_at: picker.endDate.format('YYYY-MM-DD'),
        // In this case the "date_range" param isn't being used ("start_at" and
        // "end_at" take precedence), so reset it back to the default value
        // (defined in app/controllers/stats/base.js), so it's hidden from the
        // URL.
        date_range: '14d',
      });
    }
  }

  @action
  toggleFilterType(type) {
    $('.filter-type').hide();
    $('#filter_type_' + type).show();
  }

  @action
  clickInterval(interval) {
    this.set('interval', interval);
  }

  @action
  submitForm(event) {
    event.preventDefault();
    if($('#filter_type_advanced').css('display') === 'none') {
      this.set('search', '');
      this.set('query', JSON.stringify($('#query_builder').queryBuilder('getRules')));
    } else {
      this.set('query', '');
      this.set('search', $('#filter_form input[name=search]').val());
    }
  }
}

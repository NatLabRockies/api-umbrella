import { action } from '@ember/object';
import AuthenticatedRoute from 'api-umbrella-admin-ui/routes/authenticated-route';
import bootbox from 'bootbox';
import classic from 'ember-classic-decorator';
import $ from 'jquery';
import cloneDeep from 'lodash-es/cloneDeep';
import omit from 'lodash-es/omit';
import moment from 'moment-timezone';

@classic
export default class BaseRoute extends AuthenticatedRoute {
  setupController(controller, model) {
    controller.set('model', model);
    controller.set('dateRanges', this.dateRanges);
    controller.set('presentQueryParamValues', this.presentQueryParamValues || {});
    controller.set('allQueryParamValues', this.allQueryParamValues || {});
    controller.set('backendQueryParamValues', this.backendQueryParamValues || {});

    $('ul.navbar-nav a.nav-link').removeClass('active');
    $('ul.navbar-nav li.nav-analytics > a.nav-link').addClass('active');
  }

  beforeModel() {
    super.beforeModel(...arguments);

    let timezone = this.session.data.authenticated.analytics_timezone;
    let dateRanges = {
      'today': {
        label: 'Today',
        start_at: moment().tz(timezone).startOf('day'),
        end_at: moment().tz(timezone).endOf('day'),
      },
      'yesterday': {
        label: 'Yesterday',
        start_at: moment().tz(timezone).subtract(1, 'days').startOf('day'),
        end_at: moment().tz(timezone).subtract(1, 'days').endOf('day'),
      },
      '7d': {
        label: 'Last 7 Days',
        start_at: moment().tz(timezone).subtract(6, 'days').startOf('day'),
        end_at: moment().tz(timezone).endOf('day'),
      },
      '14d': {
        label: 'Last 14 Days',
        start_at: moment().tz(timezone).subtract(13, 'days').startOf('day'),
        end_at: moment().tz(timezone).endOf('day'),
      },
      '30d': {
        label: 'Last 30 Days',
        start_at: moment().tz(timezone).subtract(29, 'days').startOf('day'),
        end_at: moment().tz(timezone).endOf('day'),
      },
      'this_month': {
        label: 'This Month',
        start_at: moment().tz(timezone).startOf('month'),
        end_at: moment().tz(timezone).endOf('month'),
      },
      'last_month': {
        label: 'Last Month',
        start_at: moment().tz(timezone).subtract(1, 'month').startOf('month'),
        end_at: moment().tz(timezone).subtract(1, 'month').endOf('month'),
      },
    };

    // If this route has the "date_range" query param set (for dynamic date
    // ranges), fill in the "start_at"/"end_at" query params based on the given
    // range. But if "start_at" or "end_at" are set, they take precedent.
    //
    // Most of our other default query params are defined in
    // controllers/stats/base.js, but Ember doesn't support dynamic query
    // params (see https://github.com/emberjs/ember.js/issues/11592), so this
    // is a bit of a workaround. We want dynamic defaults in this case for 2
    // reasons:
    //
    // 1. So that we can define the default after the session data has been
    //    fetched and we know what the default analytics timezone is.
    // 2. So that the default value changes if the user has the app open for
    //    multiple days (we don't want the default value from the very first
    //    load to never be updated again).
    let allParams = cloneDeep(this.paramsFor(this.routeName) || {});
    if(allParams.date_range) {
      let range = dateRanges[allParams.date_range];
      if(range) {
        if(!allParams.start_at) {
          allParams.start_at = range.start_at.format('YYYY-MM-DD');
        }
        if(!allParams.end_at) {
          allParams.end_at = range.end_at.format('YYYY-MM-DD');
        }
      }
    }

    this.set('dateRanges', dateRanges);
    this.set('allQueryParamValues', allParams);
    this.set('backendQueryParamValues', omit(allParams, ['date_range']));
  }

  validateParams(params) {
    let valid = true;

    let interval = params.interval;
    let start = moment(params.start_at, 'YYYY-MM-DD');
    let end = moment(params.end_at, 'YYYY-MM-DD');

    let range = end.unix() - start.unix();
    switch(interval) {
      case 'minute':
        // 2 days maximum range
        if(range > 2 * 24 * 60 * 60) {
          valid = false;
          bootbox.alert('Your date range is too large for viewing minutely data. Adjust your viewing interval or choose a date range to no more than 2 days.');
        }

        break;
      case 'hour':
        // 31 day maximum range
        if(range > 31 * 24 * 60 * 60) {
          valid = false;
          bootbox.alert('Your date range is too large for viewing hourly data. Adjust your viewing interval or choose a date range to no more than 31 days.');
        }

        break;
    }

    return valid;
  }

  @action
  queryParamsDidChange(changed, present) {
    // TODO: This call to super is within an action, and has to refer to the parent
    // class's actions to be safe. This should be refactored to call a normal method
    // on the parent class. If the parent class has not been converted to native
    // classes, it may need to be refactored as well. See
    // https: //github.com/scalvert/ember-native-class-codemod/blob/master/README.md
    // for more details.
    super.actions.queryParamsDidChange.call(this, ...arguments);
    this.set('presentQueryParamValues', present);
  }
}

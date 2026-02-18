import Helper from '@ember/component/helper';
import { inject } from '@ember/service';
import isString from 'lodash-es/isString';
import moment from 'moment-timezone';

export default class FormatDate extends Helper {
  @inject session;

  compute(positional) {
    let date = positional[0];
    let format = positional[1];

    if(!format || !isString(format)) {
      format = 'YYYY-MM-DD LT z';
    }

    if(date) {
      return moment(date).tz(this.session.data.authenticated.analytics_timezone).format(format);
    } else {
      return '';
    }
  }
}

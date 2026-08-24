import escape from 'lodash-es/escape';
import get from 'lodash-es/get';
import map from 'lodash-es/map';
import moment from 'moment-timezone';

function getName(value, options) {
  let name = value;
  if(options && options.nameField) {
    if(typeof options.nameField === 'function') {
      name = options.nameField(value);
    } else {
      name = get(value, options.nameField);
    }
  }

  return name;
}

export default {
  renderEscaped(value, type) {
    if(type === 'display') {
      if(!value) {
        return '-';
      }

      return escape(value);
    }

    return value;
  },

  renderLink(options) {
    return function(value, type, row) {
      if(type === 'display') {
        if(!value) {
          return '-';
        }

        const link = options.editLink + encodeURIComponent(get(row, options.idField)) + '/edit';
        return '<a href="' + link + '">' + escape(value) + '</a>';
      }

      return value;
    }
  },

  renderList(options) {
    return function(value, type) {
      if(type === 'display') {
        if(!value || value.length === 0) {
          return '-';
        }

        return '<ul>' + map(value, function(v) {
          return '<li>' + escape(getName(v, options)) + '</a></li>';
        }).join('') + '</ul>';
      }

      return value;
    }
  },

  renderLinkedList(options) {
    return function(value, type) {
      if(type === 'display') {
        if(!value || value.length === 0) {
          return '-';
        }

        return '<ul>' + map(value, function(v) {
          if(v.id) {
            const link = options.editLink + encodeURIComponent(v.id) + '/edit';
            return '<li><a href="' + link + '">' + escape(getName(v, options)) + '</a></li>';
          } else {
            return '<li>' + escape(getName(v, options)) + '</li>';
          }
        }).join('') + '</ul>';
      }

      return value;
    }
  },

  renderTime(timezone) {
    return function(value, type) {
      if(type === 'display' && value && value !== '-') {
        return moment(value).tz(timezone).format('YYYY-MM-DD LTS z');
      }

      return value;
    }
  },
};

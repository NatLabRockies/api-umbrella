import { config, dom, library } from '@fortawesome/fontawesome-svg-core';
import '@fortawesome/fontawesome-svg-core/styles.css';
import {
  faArrowDown,
  faArrowRight,
  faBars,
  faCalendar,
  faCaretDown,
  faCog,
  faGrip,
  faGripVertical,
  faLock,
  faMapMarkerAlt,
  faPencilAlt,
  faPlus,
  faPlusCircle,
  faQuestionCircle,
  faSignal,
  faSitemap,
  faSort,
  faSortDown,
  faSortUp,
  faSyncAlt,
  faTimes,
  faUpload,
  faUser,
  faUsers,
} from '@fortawesome/free-solid-svg-icons';
import {
  faFile,
  faFolder,
} from '@fortawesome/free-regular-svg-icons';

config.autoAddCss = false;

library.add(
  faArrowDown,
  faArrowRight,
  faBars,
  faCalendar,
  faCaretDown,
  faCog,
  faFile,
  faFolder,
  faGrip,
  faGripVertical,
  faLock,
  faMapMarkerAlt,
  faPencilAlt,
  faPlus,
  faPlusCircle,
  faQuestionCircle,
  faSignal,
  faSitemap,
  faSort,
  faSortDown,
  faSortUp,
  faSyncAlt,
  faTimes,
  faUpload,
  faUser,
  faUsers,
);

export function initialize() {
  dom.watch();
}

export default {
  name: 'fontawesome',
  initialize,
};

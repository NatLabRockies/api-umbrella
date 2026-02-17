import { setApplication } from '@ember/test-helpers';
import Application from 'api-umbrella-admin-ui/app';
import config from 'api-umbrella-admin-ui/config/environment';
import * as QUnit from 'qunit';
import { setup } from 'qunit-dom';
import { start as qunitStart, setupEmberOnerrorValidation } from 'ember-qunit';

export function start() {
  setApplication(Application.create(config.APP));

  setup(QUnit.assert);
  setupEmberOnerrorValidation();
  qunitStart();
}

import { setApplication } from '@ember/test-helpers';
import Application from 'api-umbrella-admin-ui/app';
import config from 'api-umbrella-admin-ui/config/environment';
import * as QUnit from 'qunit';
import { setup } from 'qunit-dom';
import { loadTests } from 'ember-qunit/test-loader';
import { start, setupEmberOnerrorValidation } from 'ember-qunit';

setApplication(Application.create(config.APP));

setup(QUnit.assert);
setupEmberOnerrorValidation();
loadTests();
start();

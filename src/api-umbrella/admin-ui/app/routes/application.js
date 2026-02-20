import { action } from '@ember/object';
import Route from '@ember/routing/route';
import { inject as service } from '@ember/service';
import { observes } from '@ember-decorators/object';
import isString from 'lodash-es/isString';

export default class ApplicationRoute extends Route {
  @service session;

  @service busy;

  @service currentFlashMessages;
  @service pendingFlashMessages;

  async beforeModel() {
    await this.session.setup();
  }

  // By default, ember-simple-auth sets the "session.attemptedTransition" value
  // to track where to redirect unauthenticated users to after logging in.
  // However, since we're using a server-side login page, this variable
  // disappears after the server-side login redirect. So instead, we'll store
  // just the string value of the attempted transition and persist it in the
  // session store so it's available after the server-side login.
  //
  // eslint-disable-next-line ember/no-observers
  @observes('session.attemptedTransition')
  attemptedTransitionChange() {
    const attemptedTransition = this.session.attemptedTransition;
    if(attemptedTransition) {
      this.session.set('data.attemptedTransitionUrl', attemptedTransition.intent.url);
    } else {
      this.session.set('data.attemptedTransitionUrl', null);
    }
  }

  // After successfully logging in, then redirect to the URL the user was
  // originally trying to access. Since we're using a server-side login page,
  // we need to do this a little differently than ember-simple-auth's default
  // mechanism. We need to use the "attempedTransitionUrl" string value we
  // persist in the session store.
  sessionAuthenticated() {
    const attemptedTransitionUrl = this.session.data.attemptedTransitionUrl;
    if(attemptedTransitionUrl) {
      this.transitionTo(attemptedTransitionUrl);
      this.session.set('attemptedTransition', null);
      this.session.set('data.attemptedTransitionUrl', null);
    } else {
      this.transitionTo(this.routeAfterAuthentication);
    }
  }

  @action
  loading(transition) {
    let busy = this.busy;
    busy.show();
    transition.promise.finally(function() {
      busy.hide();
    });
  }

  @action
  refreshCurrentRoute() {
    this.refresh();
    window.scrollTo(0, 0);
  }

  @action
  error(err) {
    if(err) {
      let errorMessage = err.stack
      if(!errorMessage) {
        errorMessage = err;
        // Very long text error messages can seem to hang some of the console
        // tools, so truncate the messages.
        if(isString(errorMessage)) {
          errorMessage = errorMessage.substring(0, 1000);
        }
      }
      // eslint-disable-next-line no-console
      console.error(errorMessage);
      this.busy.hide();
      return this.intermediateTransitionTo('error');
    }
  }

  @action
  didTransition() {
    // On each route change, clear any currently visible flash messages, since
    // we only want the flash messages to be visible on one page, but not
    // persistent otherwise.
    this.currentFlashMessages.empty();

    // Next, copy any "pending" flash messages that were set just before this
    // route change to the "current" messages to display. In this way, the
    // "pending" changes can be shown just once.
    for (const item of this.pendingFlashMessages.items) {
      this.currentFlashMessages.add(item);
    }

    // Clear the pending messages that have now been copied for one-time
    // display to the current area.
    this.pendingFlashMessages.empty();

    return true;
  }
}

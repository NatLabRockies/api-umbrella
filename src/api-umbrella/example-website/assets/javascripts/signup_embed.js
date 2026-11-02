// eslint-disable-next-line import/no-unresolved
import * as params from "@params";
import A11yDialog from "a11y-dialog";
import escapeHtml from "escape-html";
import serialize from "form-serialize";
import { createHashHistory } from "history";
import { createRouter } from 'franxx'

const router = createRouter({
  history: createHashHistory(),
});

const styleEl = document.createElement("link");
styleEl.rel = "stylesheet";
styleEl.type = "text/css";
styleEl.href = params.stylesheetPath;

function insertLink(root, options) {
  const link = document.createElement("link");
  link.rel = options.rel;
  link.href = options.href;
  if (options.as) {
    link.as = options.as;
  }
  root.appendChild(link);
}

function insertScript(root, options) {
  const script = document.createElement("script");
  script.type = options.type;
  script.src = options.src;
  root.appendChild(script);
}

const webSiteRoot = params.webSiteRoot.replace(/\/$/, "");

const defaultOptions = {
  containerSelector: "#api_umbrella_signup",
  apiUrlRoot: `${webSiteRoot}/api-umbrella`,
  contactUrl: `${webSiteRoot}/contact/`,
  exampleApiUrl: `${webSiteRoot}/example.json?api_key={{api_key}}`,
  signupConfirmationMessage: "",
  sendWelcomeEmail: true,
  showIntroText: false,
  showRequiredAsteriskExplainText: true,
  showFirstNameInput: true,
  showLastNameInput: true,
  showUseDescriptionInput: true,
  showWebsiteInput: false,
  showTermsInput: true,
  termsUrl: `${webSiteRoot}/terms/`,
  verifyEmail: false,
  recaptchaV2SiteKey: undefined,
  recaptchaV3SiteKey: undefined,
};

const embedOptions = window.apiUmbrellaSignupOptions || {};

// Handle legacy option names.
if (
  embedOptions.showWebsiteInput === undefined &&
  embedOptions.websiteInput !== undefined
) {
  embedOptions.showWebsiteInput = embedOptions.websiteInput;
}
if (
  embedOptions.showTermsInput === undefined &&
  embedOptions.termsCheckbox !== undefined
) {
  embedOptions.showTermsInput = embedOptions.termsCheckbox;
}

const options = {
  ...defaultOptions,
  ...embedOptions,
};

if (!options.apiKey) {
  // eslint-disable-next-line no-alert
  alert("apiUmbrellaSignupOptions.apiKey must be set");
}

if (!options.registrationSource) {
  // eslint-disable-next-line no-alert
  alert("apiUmbrellaSignupOptions.registrationSource must be set");
}

let signupFormTemplate = "";
let recaptchaV2Enabled = !!options.recaptchaV2SiteKey;
let recaptchaV2WidgetId;
let recaptchaV2Response;
let recaptchaV2SubmitButtonTimeout;
let recaptchaV3Enabled = !!options.recaptchaV3SiteKey;
let recaptchaV3WidgetId;
let recaptchaV3Response;

if (options.showIntroText) {
  signupFormTemplate += `
    <p>Sign up for an application programming interface (API) key to access and use web services.</p>
  `;
}

if (options.showRequiredAsteriskExplainText) {
  signupFormTemplate += `
    <p class="required-fields">Required fields are marked with an asterisk (<abbr title="required" class="required">*</abbr>).</p>
  `;
}

signupFormTemplate += `
  <form id="api_umbrella_signup_form" novalidate>
`;

if (options.showFirstNameInput) {
  signupFormTemplate += `
    <div class="form-group first-name-form-group">
      <label class="form-label" for="user_first_name">First Name <abbr title="required" class="required">*</abbr></label>
      <input class="form-control" id="user_first_name" aria-describedby="user_first_name_feedback" name="user[first_name]" size="50" type="text" required />
      <div id="user_first_name_feedback" class="invalid-feedback">Fill out this field.</div>
    </div>
  `;
} else {
  signupFormTemplate += `<input type="hidden" name="user[first_name]" value="${escapeHtml(
    options.registrationSource,
  )} User" />`;
}

if (options.showLastNameInput) {
  signupFormTemplate += `
    <div class="form-group last-name-form-group">
      <label class="form-label" for="user_last_name">Last Name <abbr title="required" class="required">*</abbr></label>
      <input class="form-control" id="user_last_name" aria-describedby="user_last_name_feedback" name="user[last_name]" size="50" type="text" required />
      <div id="user_last_name_feedback" class="invalid-feedback">Fill out this field.</div>
    </div>
  `;
} else {
  signupFormTemplate += `<input type="hidden" name="user[last_name]" value="${escapeHtml(
    options.registrationSource,
  )} User" />`;
}

signupFormTemplate += `
  <div class="form-group email-form-group">
    <label class="form-label" for="user_email">Email <abbr title="required" class="required">*</abbr></label>
    <input class="form-control" id="user_email" aria-describedby="user_email_feedback" name="user[email]" size="50" type="email" required />
    <div id="user_email_feedback" class="invalid-feedback">Enter an email address.</div>
  </div>
`;

if (options.showWebsiteInput) {
  signupFormTemplate += `
    <div class="form-group website-form-group">
      <label class="form-label" for="user_website">Website (optional)</label>
      <input class="form-control" id="user_website" aria-describedby="user_website_feedback" name="user[website]" size="50" type="url" placeholder="https://" />
      <div id="user_website_feedback" class="invalid-feedback">Enter a URL.</div>
    </div>
  `;
}

if (options.showUseDescriptionInput) {
  signupFormTemplate += `
    <div class="form-group use-description-form-group">
      <label class="form-label" for="user_use_description">How will you use the APIs? (optional)</label>
      <textarea class="form-control" cols="40" id="user_use_description" name="user[use_description]" rows="2"></textarea>
    </div>
  `;
}

if (options.showTermsInput) {
  signupFormTemplate += `
    <div class="form-group terms-form-group">
      <div class="form-check">
        <input id="user_terms_and_conditions" aria-describedby="user_terms_and_conditions_feedback" name="user[terms_and_conditions]" type="checkbox" class="form-check-input" value="true" required />
        <label class="form-check-label" for="user_terms_and_conditions">I have read and agree to the <a href="${escapeHtml(
          options.termsUrl,
        )}" onclick="window.open(this.href, &#x27;api_umbrella_terms&#x27;, &#x27;height=500,width=790,menubar=no,toolbar=no,location=no,personalbar=no,status=no,resizable=yes,scrollbars=yes&#x27;); return false;" title="Opens new window to terms and conditions">terms and conditions</a>.</label>
        <div id="user_terms_and_conditions_feedback" class="invalid-feedback">You must agree to the terms and conditions to signup.</div>
      </div>
    </div>
  `;
} else {
  signupFormTemplate += `<input type="hidden" name="user[terms_and_conditions]" value="true" />`;
}

signupFormTemplate += `
  <div class="submit">
    <input type="hidden" name="user[registration_source]" value="${escapeHtml(
      options.registrationSource,
    )}" />
    <button type="submit" class="btn btn-lg btn-primary" data-loading-text="Loading...">Sign up</button>
  </div>

  <p class="mt-4 mb-0">To disable or revoke an existing key, <a href="#/deactivate-api-key">begin API key deactivation</a>.</p>
`;

if (recaptchaV2Enabled || recaptchaV3Enabled) {
  signupFormTemplate += `<div class="recaptcha-notice">This site is protected by reCAPTCHA and the Google <a href="https://policies.google.com/privacy">Privacy Policy</a> and <a href="https://policies.google.com/terms">Terms of Service</a> apply.</div>`;
}

signupFormTemplate += `</form>`;

const formModalTemplate = `
  <div id="api_umbrella_form_modal" class="dialog-container" aria-labelledby="api_umbrella_form_modal_title" aria-hidden="true">
    <div class="modal-backdrop show" data-a11y-dialog-hide></div>
    <div role="document" class="modal show d-block">
      <div class="modal-dialog modal-lg">
        <div class="modal-content shadow">
          <div class="modal-header">
            <h1 class="h4 mb-0 modal-title" id="api_umbrella_form_modal_title"></h1>
            <button type="button" class="btn-close" aria-label="Close" data-a11y-dialog-hide></button>
          </div>
          <div class="modal-body" id="api_umbrella_form_modal_body">
          </div>
        </div>
      </div>
    </div>
  </div>
`;

const alertModalTemplate = `
  <div id="api_umbrella_alert_modal" class="dialog-container" aria-labelledby="api_umbrella_alert_modal_title" aria-hidden="true">
    <div class="modal-backdrop show" data-a11y-dialog-hide></div>
    <div role="document" class="modal show d-block">
      <div class="modal-dialog mt-5">
        <div class="modal-content shadow">
          <div class="modal-header">
            <h1 class="h4 mb-0 modal-title" id="api_umbrella_alert_modal_title">Error</h1>
            <button type="button" class="btn-close" aria-label="Close" data-a11y-dialog-hide></button>
          </div>
          <div class="modal-body" id="api_umbrella_alert_modal_body">
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-primary" data-a11y-dialog-hide>OK</button>
          </div>
        </div>
      </div>
    </div>
  </div>
`;

const requestDeactivationFormTemplate = `
  <p>To disable or revoke an existing API key, email confirmation is required.</p>

  <form id="api_umbrella_request_deactivation_form" novalidate>
    <div class="form-group api-key-form-group">
      <label class="form-label" for="user_api_key">API Key <abbr title="required" class="required">*</abbr></label>
      <input class="form-control" id="user_api_key" aria-describedby="user_api_key user_api_key" name="user[api_key]" size="50" type="text" minlength="40" maxlength="40" required />
      <div class="form-text" id="user_api_key">Provide the full API key you want to deactivate.</div>
      <div id="user_api_key" class="invalid-feedback">Enter a full API key.</div>
    </div>

    <div class="form-group email-form-group">
      <label class="form-label" for="user_email">Email <abbr title="required" class="required">*</abbr></label>
      <input class="form-control" id="user_email" aria-describedby="user_email_hint user_email_feedback" name="user[email]" size="50" type="email" required />
      <div class="form-text" id="user_email_hint">Provide the email address used to sign up for the API key with.</div>
      <div id="user_email_feedback" class="invalid-feedback">Enter an email address.</div>
    </div>

    <div class="submit">
      <button type="submit" class="btn btn-lg btn-primary" data-loading-text="Loading...">Send confirmation email</button>
    </div>
  </form>
`;

const containerEl = document.querySelector(options.containerSelector);
containerEl.textContent = "";
const containerContentEl = document.createElement("div");
containerContentEl.className = "api-umbrella-signup-embed-content-container";
containerEl.appendChild(containerContentEl);
const containerShadowRootEl = containerContentEl.attachShadow({ mode: "open" });

// The recaptcha elements need to exist outside of the shadow DOM for recaptcha
// compatibility.
let recaptchaV2El;
if (recaptchaV2Enabled) {
  recaptchaV2El = document.createElement("div");
  recaptchaV2El.className = "api-umbrella-signup-embed-recaptcha-v2";
  recaptchaV2El.style = "visibility: hidden;";
  containerEl.appendChild(recaptchaV2El);
}
let recaptchaV3El;
if (recaptchaV3Enabled) {
  recaptchaV3El = document.createElement("div");
  recaptchaV3El.className = "api-umbrella-signup-embed-recaptcha-v3";
  recaptchaV3El.style = "visibility: hidden;";
  containerEl.appendChild(recaptchaV3El);
}

// Compute how big the font size is wherever the container is being injected
// and then compare that to the root font size, so we can fix `rem` units with
// the help of https://github.com/GUI/postcss-relative-rem
const rootFontSize = parseFloat(
  window
    .getComputedStyle(document.documentElement)
    .getPropertyValue("font-size"),
);
const containerFontSize = parseFloat(
  window.getComputedStyle(containerEl).getPropertyValue("font-size"),
);
const remRelativeBaseSize = `${containerFontSize / rootFontSize}rem`;

const containerStyleRootEl = document.createElement("div");
containerStyleRootEl.className = "app-style-root";
containerStyleRootEl.innerHTML = signupFormTemplate;
containerStyleRootEl.style.setProperty(
  "--api-umbrella-rem-relative-base",
  remRelativeBaseSize,
);
containerShadowRootEl.appendChild(containerStyleRootEl);

const bodyContainerEl = document.createElement("div");
bodyContainerEl.id = "api-umbrella-signup-embed-body-container";
const bodyContainerShadowRootEl = bodyContainerEl.attachShadow({
  mode: "open",
});
const bodyContainerStyleRootEl = document.createElement("div");
bodyContainerStyleRootEl.className = "app-style-root";
bodyContainerStyleRootEl.innerHTML = formModalTemplate + alertModalTemplate;
bodyContainerStyleRootEl.style.setProperty(
  "--api-umbrella-rem-relative-base",
  remRelativeBaseSize,
);
bodyContainerShadowRootEl.appendChild(bodyContainerStyleRootEl);
document.body.appendChild(bodyContainerEl);

insertLink(containerShadowRootEl, {
  rel: "stylesheet",
  href: params.stylesheetPath,
});

insertLink(bodyContainerShadowRootEl, {
  rel: "stylesheet",
  href: params.stylesheetPath,
});

const formModalEl = bodyContainerShadowRootEl.getElementById("api_umbrella_form_modal");
const formModalBodyEl = formModalEl.querySelector("#api_umbrella_form_modal_body");
const formModal = new A11yDialog(formModalEl);
formModal.on('hide', (event) => {
  if (router.currentLocation.pathname !== '/') {
    router.push('/');
  }
});

const alertModalEl = bodyContainerShadowRootEl.getElementById("api_umbrella_alert_modal");
const alertModalBodyEl = alertModalEl.querySelector("#api_umbrella_alert_modal_body");
const alertModal = new A11yDialog(alertModalEl);

// Setup close handlers for a11y-dialog when inside the shadow DOM (since their
// default document listeners won't work).
formModalEl.querySelectorAll("[data-a11y-dialog-hide]").forEach((closer) => {
  closer.addEventListener("click", formModal.hide);
});
alertModalEl.querySelectorAll("[data-a11y-dialog-hide]").forEach((closer) => {
  closer.addEventListener("click", alertModal.hide);
});

const formEl = containerShadowRootEl.querySelector("form");
const submitButtonEl = formEl.querySelector("button[type=submit]");

function disableSubmitButton(buttonEl) {
  if (!buttonEl.disabled) {
    buttonEl.dataset.origInnerHTML = submitButtonEl.innerHTML;
    buttonEl.disabled = true;
    buttonEl.innerText = "Loading...";
  }
}

function enableSubmitButton(buttonEl) {
  if (submitButtonEl.disabled) {
    buttonEl.disabled = false;
    buttonEl.innerHTML = submitButtonEl.dataset.origInnerHTML;
    delete buttonEl.dataset.origInnerHTML;
  }
}

function submitFetch(submitOptions) {
  return fetch(submitOptions.url, {
    method: (submitOptions.data) ? "POST" : "GET",
    headers: {
      "Content-Type": (submitOptions.data) ? "application/json" : undefined,
      "X-Api-Key": options.apiKey,
    },
    body: (submitOptions.data) ? JSON.stringify(submitOptions.data) : undefined,
    // Ensure admin credentials aren't sent in for signed in admins.
    credentials: "omit",
  })
    .then((response) => {
      const contentType = response.headers.get("Content-Type");
      if (!contentType || !contentType.includes("application/json")) {
        throw new Error("Response is not JSON");
      }

      return response.json().then((data) => ({
        response,
        data,
      }));
    })
    .then(({ response, data }) => {
      if (!response.ok) {
        // eslint-disable-next-line no-throw-literal
        throw { responseData: data };
      }

      submitOptions.onSuccess(data);
    })
    .catch((error) => {
      const messages = [];
      let messageStr = "";
      try {
        if (error?.responseData?.errors) {
          for (let i = 0; i < error.responseData.errors.length; i += 1) {
            const err = error.responseData.errors[i];
            if (err.full_message || err.message) {
              messages.push(escapeHtml(err.full_message || err.message));
            }
          }
        }

        if (error?.responseData?.error?.message) {
          messages.push(escapeHtml(error.responseData.error.message));
        }

        if (messages.length > 0) {
          messageStr = `<ul><li>${messages.join("</li><li>")}</li></ul>`;
        } else {
          // eslint-disable-next-line no-console
          console.error(error);
        }
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error(e);
      }

      alertModalBodyEl.innerHTML = `
        ${submitOptions.errorIntro}
        ${messageStr}
        ${submitOptions.errorOutro}
      `;
      alertModal.show();
    })
    .finally(enableSubmitButton.bind(null, submitButtonEl));
}

function apiKeyRegistrationFetch() {
  const formData = {
    ...serialize(formEl, { hash: true }),
    options: {
      example_api_url: options.exampleApiUrl,
      contact_url: options.contactUrl,
      site_name: options.siteName,
      send_welcome_email: options.sendWelcomeEmail,
      email_from_name: options.emailFromName,
      email_from_address: options.emailFromAddress,
      verify_email: options.verifyEmail,
    },
  };

  if (formData?.user?.terms_and_conditions === "true") {
    formData.user.terms_and_conditions = true;
  }

  if (recaptchaV2Enabled) {
    formData["g-recaptcha-response-v2"] = recaptchaV2Response;
  }

  if (recaptchaV3Enabled) {
    formData["g-recaptcha-response-v3"] = recaptchaV3Response;
  }

  return submitFetch({
    url: `${options.apiUrlRoot}/v1/users.json`,
    data: formData,
    onSuccess: (data) => {
      const { user } = data;

      let confirmationTemplate = "";
      if (data.options.verify_email) {
        confirmationTemplate += `
          <p>Your API key for <strong>${escapeHtml(
            user.email,
          )}</strong> has been emailed to you. You can use your API key to begin making web service requests immediately.</p>
          <p>If you don't receive your API Key via email within a few minutes, please <a href="${escapeHtml(
            data.options.contact_url,
          )}">contact us</a>.</p>
        `;
      } else {
        confirmationTemplate += `
          <p>Your API key for <strong>${escapeHtml(user.email)}</strong> is:</p>
          <pre class="signup-key"><code>${escapeHtml(user.api_key)}</code></pre>
          <p>You can start using this key to make web service requests. Simply pass your key in the URL when making a web request. Here's an example:</p>
          <pre class="signup-example"><a href="${escapeHtml(
            data.options.example_api_url,
          )}">${data.options.example_api_url_formatted_html}</a></pre>
        `;
      }

      confirmationTemplate += `
        ${options.signupConfirmationMessage}
        <div class="signup-footer">
          <p>For additional support, please <a href="${escapeHtml(
            data.options.contact_url,
          )}">contact us</a>. When contacting us, please tell us what API you're accessing and provide the following account details so we can quickly find you:</p>
          Account Email: ${escapeHtml(user.email)}<br>
          Account ID: ${escapeHtml(user.id)}
        </div>
      `;

      containerStyleRootEl.innerHTML = confirmationTemplate;
      containerStyleRootEl.tabIndex = -1;
      containerStyleRootEl.focus();
      containerStyleRootEl.scrollIntoView();
    },
    errorIntro: `<p>API key signup unexpectedly failed.</p>`,
    errorOutro: `
      <p class="mb-0">
        Please try again or <a href="${escapeHtml(
          options.issuesUrl,
        )}">file an issue</a> for assistance.
      </p>
    `,
  });
}

function requestDeactivationFetch(formEl) {
  const formData = {
    ...serialize(formEl, { hash: true }),
    options: {
      submitted_from_url: window.location.href,
    },
  };

  return submitFetch({
    url: `${options.apiUrlRoot}/v1/users/request-deactivation.json`,
    data: formData,
    onSuccess: () => {
      let confirmationTemplate = `
        <p>Instructions for deactivating your API key have been emailed to <strong>${escapeHtml(formData.user.email)}</strong>.;

        <p>If you don't receive instructions via e-mail within a few minutes, please check your junk mail.
      `;

      formModalBodyEl.innerHTML = confirmationTemplate;
    },
    errorIntro: '',
    errorOutro: 'Please resolve the errors and try again.',
  });
}

function confirmDeactivationFetch(formEl) {
  const formData = {
    ...serialize(formEl, { hash: true }),
    options: {
      submitted_from_url: window.location.href,
    },
  };

  return submitFetch({
    url: `${options.apiUrlRoot}/v1/users/confirm-deactivation.json`,
    data: formData,
    onSuccess: () => {
      let confirmationTemplate = `
        <p>Instructions for deactivating your API key have been emailed to <strong>${escapeHtml(formData.user.email)}</strong>.;

        <p>If you don't receive instructions via e-mail within a few minutes, please check your junk mail.
      `;

      formModalBodyEl.innerHTML = confirmationTemplate;
    },
    errorIntro: '',
    errorOutro: 'Please resolve the errors and try again.',
  });
}

function recaptchaCallback() {
  if (recaptchaV2Enabled) {
    recaptchaV2Response = window.grecaptcha.getResponse(recaptchaV2WidgetId);

    // If the possible captcha prompt was solved, then we can disable out
    // submit button timeout workaround and disable the submit button again
    // until the actual submission finishes.
    if (recaptchaV2Response) {
      if (recaptchaV2SubmitButtonTimeout) {
        clearTimeout(recaptchaV2SubmitButtonTimeout);
        recaptchaV2SubmitButtonTimeout = null;
      }

      disableSubmitButton(submitButtonEl);
    }
  }

  if (recaptchaV3Enabled) {
    recaptchaV3Response = window.grecaptcha.getResponse(recaptchaV3WidgetId);
  }

  if (
    ((recaptchaV2Enabled && recaptchaV2Response) || !recaptchaV2Enabled) &&
    ((recaptchaV3Enabled && recaptchaV3Response) || !recaptchaV3Enabled)
  ) {
    apiKeyRegistrationFetch();
  }
}

window.apiUmbrellaRecaptchaLoadCallback =
  function apiUmbrellaRecaptchaLoadCallback() {
    if (recaptchaV2Enabled) {
      recaptchaV2WidgetId = window.grecaptcha.render(recaptchaV2El, {
        sitekey: options.recaptchaV2SiteKey,
        size: "invisible",
        isolated: true,
        callback: recaptchaCallback,
        "error-callback": () => {
          // TODO: Make error fatal (rather than disabling), once we want to
          // start enforcing recaptcha use.
          recaptchaV2Enabled = false;
          // eslint-disable-next-line no-console
          console.error("recaptcha v2 render error");
        },
      });
    }

    if (recaptchaV3Enabled) {
      recaptchaV3WidgetId = window.grecaptcha.render(recaptchaV3El, {
        sitekey: options.recaptchaV3SiteKey,
        size: "invisible",
        isolated: true,
        callback: recaptchaCallback,
        "error-callback": () => {
          // TODO: Make error fatal (rather than disabling), once we want to
          // start enforcing recaptcha use.
          recaptchaV3Enabled = false;
          // eslint-disable-next-line no-console
          console.error("recaptcha v3 render error");
        },
      });
    }
  };

if (recaptchaV2Enabled || recaptchaV3Enabled) {
  insertScript(document.body, {
    src: `https://www.google.com/recaptcha/api.js?render=explicit&onload=apiUmbrellaRecaptchaLoadCallback`,
    type: "text/javascript",
    async: true,
    defer: true,
  });
}

function handleSubmit(event, formEl, formHasRecaptcha, submitAction) {
  event.preventDefault();
  disableSubmitButton(submitButtonEl);

  if (!formEl.checkValidity()) {
    formEl.classList.add("was-validated");
    // Focus on the first invalid input.
    formEl.reportValidity();
    enableSubmitButton(submitButtonEl);
    return false;
  }

  // If recaptcha never loaded (eg, due to CSP), disable for now until we
  // complete the required rollout.
  //
  // TODO: Make error fatal (rather than disabling), once we want to start
  // enforcing recaptcha use.
  if (!window.grecaptcha || !window.grecaptcha.execute) {
    recaptchaV2Enabled = false;
    recaptchaV3Enabled = false;
  }

  if (recaptchaV2Enabled || recaptchaV3Enabled) {
    try {
      if (recaptchaV2Enabled) {
        // Re-enable the submit button after a period of time in case the user
        // is prompted with the captcha solve screen and chooses to close it.
        // This is a bit of a workaround but since recpatcha doesn't support a
        // close event, this will at least ensure the button gets re-enabled
        // without messing with more complicated DOM monitoring solutions.
        //
        // https://stackoverflow.com/a/44984658
        // https://stackoverflow.com/a/47949586
        recaptchaV2SubmitButtonTimeout = setTimeout(enableSubmitButton, 3000, submitButtonEl);

        recaptchaV2Response = null;
        window.grecaptcha
          .execute(recaptchaV2WidgetId)
          .then(() => {
            // I don't think this should be possible, but if `error-callback`
            // was called between `execute` and `then`, make sure we still call
            // our normal callback (which handles the situation of recaptcha
            // being disabled).
            //
            // TODO: Remove once we start enforcing recaptcha, in which case we
            // won't need to submit if `error-callback` was called.
            if (!recaptchaV2Enabled) {
              recaptchaCallback();
            }
          })
          .catch((e) => {
            // eslint-disable-next-line no-console
            console.error("recaptcha v2 execute catch: ", e);
            recaptchaV2Enabled = false;
            recaptchaCallback();
          });
      }

      if (recaptchaV3Enabled) {
        recaptchaV3Response = null;
        window.grecaptcha
          .execute(recaptchaV3WidgetId, { action: "signup" })
          .then(() => {
            // I don't think this should be possible, but if `error-callback`
            // was called between `execute` and `then`, make sure we still call
            // our normal callback (which handles the situation of recaptcha
            // being disabled).
            //
            // TODO: Remove once we start enforcing recaptcha, in which case we
            // won't need to submit if `error-callback` was called.
            if (!recaptchaV3Enabled) {
              recaptchaCallback();
            }
          })
          .catch((e) => {
            // eslint-disable-next-line no-console
            console.error("recaptcha v3 execute catch: ", e);
            recaptchaV3Enabled = false;
            recaptchaCallback();
          });
      }
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("recaptcha error: ", e);
      // eslint-disable-next-line no-alert
      alert(
        "Unexpected error occurred while validating CAPTCHA. Please try again or contact us for assistance",
      );
      enableSubmitButton(submitButtonEl);
    }
  } else {
    submitAction();
  }

  return undefined;
};

formEl.addEventListener("submit", (event) => {
  handleSubmit(event, formEl, true, apiKeyRegistrationFetch);
});

router.add('/deactivate-api-key', ({ params, query }) => {
  formModalEl.querySelector('h1').innerHTML = 'Deactivate an API Key';
  formModalBodyEl.innerHTML = requestDeactivationFormTemplate;
  formModal.show();

  const formEl = formModalBodyEl.querySelector("form");
  const submitButtonEl = formEl.querySelector("button[type=submit]");

  formEl.addEventListener("submit", (event) => {
    handleSubmit(event, formEl, false, requestDeactivationFetch.bind(null, formEl));
  });
})

router.add('/confirm-deactivation', ({ params, query }) => {
  formModalEl.querySelector('h1').innerHTML = 'Deactivate an API Key';
  formModalBodyEl.innerHTML = '<p>Loading...</p>';
  formModal.show();

  const url = new URL(`${options.apiUrlRoot}/v1/users/confirm-deactivation.json`);
  url.search = new URLSearchParams({ token: query.token }).toString();
  submitFetch({
    url: url,
    onSuccess: (data) => {
      formModalBodyEl.innerHTML = `
        <p><strong>The API key is still active.</strong> To complete the deactivation process, review the details below and confirm your request.</p>

        <ul>
          <li><strong>API Key:</strong> <code>...${escapeHtml(data.user.api_key_suffix)}</code></li>
          <li><strong>Key Created:</strong> ${escapeHtml(data.user.created_at)}</li>
        </ul>

        <p>Are you sure you want to deactivate this key? Once deactivated, requests using this API key will fail.</p>

        <form id="api_umbrella_confirm_deactivation_form" novalidate>
          <input type="hidden" name="user[deactivation_token]" value="${escapeHtml(query.token)}" />

          <div class="form-actions">
            <button type="submit" class="btn btn-lg btn-primary" data-loading-text="Loading...">Deactivate this API key</button>
          </div>
        </form>
      `;

      const formEl = formModalBodyEl.querySelector("form");
      const submitButtonEl = formEl.querySelector("button[type=submit]");

      formEl.addEventListener("submit", (event) => {
        handleSubmit(event, formEl, false, confirmDeactivationFetch.bind(null, formEl));
      });
    },
    errorIntro: '',
    errorOutro: 'Please resolve the errors and try again.',
  });
})


router.add('*', () => {
  if (formModal.shown) {
    formModal.hide();
  }
})

router.run()

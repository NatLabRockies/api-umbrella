# API Umbrella Change Log

## 0.15.1 (2019-05-14)

👋 Long time no release! Sorry for the long gap since our last formal release, but we have a sizable upgrade ready that fixes various bugs, and makes a lot of internal improvements. Upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Fixed

- **Fix filtering admin analytics on the "HTTP Method" field:** Analytics filters for the "HTTP Method" field were not working. ([api.data.gov#401](https://github.com/18F/api.data.gov/issues/401), [#389](https://github.com/NREL/api-umbrella/issues/389))
- **Fix admins without admin management permissions accessing their own account page:** If an admin account didn't also have "Admin Accounts - View & Manage" permissions, the admin wasn't able to access their own admin account page. ([api.data.gov#451](https://github.com/18F/api.data.gov/issues/451), [api.data.gov#443](https://github.com/18F/api.data.gov/issues/443))
- **Fix admin navigation links not hiding based on admin account permissions:** Admin accounts with limited permissions were still being shown links to all the possible admin pages, even if they didn't have permissions to those pages. This is fixed so there are only navigation links to the permitted admin areas now. ([api.data.gov#432](https://github.com/18F/api.data.gov/issues/432), [api.data.gov#394](https://github.com/18F/api.data.gov/issues/394))
- **Fix admins with limited permissions not able to publish website backends:** Only superuser admins were able to publish website backend changes. ([9091de9](https://github.com/NREL/api-umbrella/commit/9091de98edf40920733cfc91e7101456a9d604fd), [0356c6b](https://github.com/NREL/api-umbrella/commit/0356c6badb30ada82300d0ed6651604ff7ec3f13))
- **Fix CSV download for admin drilldown analytics:** The CSV download link in the API Drilldown part of the admin analytics wasn't working. ([api.data.gov#410](https://github.com/18F/api.data.gov/issues/410))
- **Fix missing column headers in admin analytics "Filter Logs" CSVs:** Some of the last columns of data in this CSV were missing the associated column headers. ([api.data.gov#480](https://github.com/18F/api.data.gov/issues/480))
- **Fix out-of-memory issues potentially leading to outage:** In the event the API backend configuration exceeds the allocated memory for this configuration in nginx (configured via `nginx.shared_dicts.active_config.size`), the API backend configuration could become unloaded leading to an API outage. This is now fixed so that the new API backend configuration will only get published if there's enough available memory (otherwise, the old configuration will remain in place, and a warning will be logged). The default memory size for this configuration has also been increased to allow for 750-1000 API backends by default (up from the previous default allowing 150-300 API backends). ([cb5e2c1](https://github.com/NREL/api-umbrella/commit/cb5e2c1876d59dde947ad635cada955683c5afa5), [3af5700](https://github.com/NREL/api-umbrella/commit/3af5700f5b2b47d4cbac60794bed2a02758d95cd), [api.data.gov#385](https://github.com/18F/api.data.gov/issues/385))
- **Fix URL handling for query strings containing "api\_key":** It was possible that API Umbrella was stripping the string "api\_key" from inside URLs before passing requests to the API backend in some unexpected cases. The `api_key` query parameter should still be stripped, but other instances of "api\_key" elsewhere in the URL (for example as a value, like `?foo=api_key`), are now retained. ([de3e207](https://github.com/NREL/api-umbrella/commit/de3e207d07a65664abc38a9374df1e9611ffee31))
- **Fix behavior of drilldown chart in admin analtyics:** The behavior of the drilldown chart in the analtyics area could sporadically be incorrect and render the wrong data in the chart. ([api.data.gov#433](https://github.com/18F/api.data.gov/issues/433))
- **Fix redirect rewriting from API backends:** When an API backend returns a redirect, there were some situations where the rewritten redirect would be incorrect (if API Umbrella was running on a custom HTTP or HTTPS port, or in situations where the API backend has multiple URL prefix matches, or if the API backend returns an already rewritten path). ([735212b](https://github.com/NREL/api-umbrella/commit/735212b1dd77dab104541f53521a47e76c6ef063), [4d5cc3f](https://github.com/NREL/api-umbrella/commit/4d5cc3fcb6838e0d804ad9d7c80d40e83c78b045))
- **Fix configuration settings to extend the default HTTP timeout:** Fix the `nginx.proxy_read_timeout` and `nginx.proxy_connect_timeout` settings for use with API backends that are slower to respond. ([#441](https://github.com/NREL/api-umbrella/issues/441), [17bc65c](https://github.com/NREL/api-umbrella/commit/17bc65c8e35b1d950b11adb4847da9a201e24889))
- **Fix empty 404 and 500 error pages served from web-app:** If the web-app returned 404 or 500 errors, these were returned with an empty response body in v0.14.0+. ([a6fb68e](https://github.com/NREL/api-umbrella/commit/a6fb68edabb30670d18c63f68e0f590e52d70b7d))
- **Fix memory leaks:** Remove background task to periodically reload nginx due to unexpected memory growth which is now fixed. ([09b3f74](https://github.com/NREL/api-umbrella/commit/09b3f74423588d44cb0c6486a54ff5ce2edc21f4))
- **Fix admin logouts when API Umbrella is restarted:** The randomized secret token used for session encryption could be regenerated on API Umbrella restarts, which could lead to admins needing to login again. ([c65ea2f](https://github.com/NREL/api-umbrella/commit/c65ea2f746cbe5a015b03dadcd3d63034659be73), [f88a2c0](https://github.com/NREL/api-umbrella/commit/f88a2c020a0a341fc7dc5c2f6d3460df570a3f5b))
- **Fix admin analytics when no indices for the date range are present:** If querying the analytics for date ranges where no analytics indices were present, ensure that the API still responds successfully (with 0 values). ([c743e79](https://github.com/NREL/api-umbrella/commit/c743e79ad904a140cc7427cacf4fddf51bb9c1a4))
- **Fix nginx warnings:** Fix warnings generated in the nginx log files. ([04e8c9c](https://github.com/NREL/api-umbrella/commit/04e8c9cec84eaa4b2f3b8d8691de0b1899f9adc9), [08b59e7](https://github.com/NREL/api-umbrella/commit/08b59e7a3da587670850da0cd75f2a5cc55a3360))
- **Fix edge case with seeded API keys having the same key:** It was possible that the API keys created during startup for internal usage could end up having duplicate, colliding API key values. This likely only affected the test environment when repeated, rapid reload were performed. ([a725342](https://github.com/NREL/api-umbrella/commit/a7253421d8eebb160b23c1bd75b278d00f5d9dc3), [8fd99e3](https://github.com/NREL/api-umbrella/commit/8fd99e3b24db683ad129d89dfe266becf77f2ef2))
- **Fix edge cases to handle MongoDB replicaset changes more gracefully:** Better handle errors during MongoDB replicaset changes to retry queries. ([a808feb](https://github.com/NREL/api-umbrella/commit/a808febef494358985f8c518ee0938a1520cec3f))
- **Improve keepalive handling:** Fix possibility of 502 Bad Gateway responses in cases where an API backend closes a keepalive connection to API Umbrella. ([833e3de](https://github.com/NREL/api-umbrella/commit/833e3de24a5068e1ed57aa044d12b8df68f529f3), [api.data.gov#446](https://github.com/18F/api.data.gov/issues/446))
- **Fix edge case with rapid reloads causing config data to go missing:** If rapidly reloading the API Umbrella process, the config could go missing. This likely only affected our test suite which performs rapid reloads. ([e274d86](https://github.com/NREL/api-umbrella/commit/e274d8697b8d377d40f73bcde5a5aca721546740))

### Security

- **Prevent API URLs and contact URLs from linking to unknown domains in API key signup e-mails:** Someone could trigger an API key signup e-mail to a user with links to unexpected locations for the example API URL or "contact us" link. Thanks to [@nuke11](https://hackerone.com/nuke11) for the bug bounty report. ([api.data.gov#460](https://github.com/18F/api.data.gov/issues/460))
- **XSS issue in flash error messages from external login providers:** Error messages from external login providers (eg, Google) could contain a cross-site scripting (XSS) vulnerability. ([469572c](https://github.com/NREL/api-umbrella/commit/469572c73991975b7d90b86e98eeb5a0e1b8528e))
- **Prevent admin groups from having analytics permissions:** If an admin account belonged to only admin groups that didn't have any analytics permissions, then it was possible they admin could inadvertently view all analytics data. ([a4569a6](https://github.com/NREL/api-umbrella/commit/a4569a623380f7d1ecc897ff3078a721cfd51642))

### Added
- **Added packages for Ubuntu 18.04 and Debian 9:** Pre-packaged binaries are now available for the latest Debian and Ubuntu LTS releases. ([#432](https://github.com/NREL/api-umbrella/issues/432), [#444](https://github.com/NREL/api-umbrella/issues/444))
- **Elasticsearch V5, V6, and V7 compatibility:** If using an external Elasticsearch database, API Umbrella now support Elasticsearch versions 5, 6, and 7. The `elasticsearch.api_version` must be adjusted accordingly. ([#393](https://github.com/NREL/api-umbrella/issues/393))
- **Elasticsearch SSL support:** You can now point to an Elasticsearch URL over HTTPS. ([a201220](https://github.com/NREL/api-umbrella/commit/a201220ec1736c3db1cb94190b3e7fd6faffee24), [a5a403f](https://github.com/NREL/api-umbrella/commit/a5a403fb0690cb2484d37466cd5e5efcb6494642), [d89960f](https://github.com/NREL/api-umbrella/commit/d89960fbc5be7f6fa6ef12e4dbd9e94d72920285))
- **AWS Elasticsearch signing for IAM access control:** There is an extra proxy layer to support using AWS Elasticsearch when using IAM for access control. ([9ddce5e](https://github.com/NREL/api-umbrella/commit/9ddce5e92627390afb42c127d951776b6041c23a))
- **Option to log all output to stdout/stderr:** The `log.destination: console` option can be used to log all output to stdout/stderr instead of log files. This makes API Umbrella easier to run in containerized environments. ([#376](https://github.com/NREL/api-umbrella/issues/376))
- **Options to parse client IPs from different HTTP headers:** If other proxies are present in front of API Umbrella, additional options have been added to parse the original client's IP address from a different HTTP header. ([api.data.gov#429](https://github.com/18F/api.data.gov/issues/429), [#431](https://github.com/NREL/api-umbrella/issues/431))
- **Option to perform HTTPS redirects on specific API URLs:** The `router.api_backend_required_https_regex_default` configuration option can be used to force certain API URLs to redirect to HTTPS based on a regex. ([api.data.gov#457](https://github.com/18F/api.data.gov/issues/457))
- **Configurable API user validation regexes:** Regexes to validate e-mail addresses, first names, and last names for API key signups are now configurable (`web.api_user.email_regex`, `web.api_user.first_name_exclude_regex`, `web.api_user.last_name_exclude_regex`). ([15f14f3](https://github.com/NREL/api-umbrella/commit/15f14f3cad9bb4857b630a7f8e932258d84240ff), [1566eef](https://github.com/NREL/api-umbrella/commit/1566eeff4034dcb2cb8600b9788479c2b1126063))
- **Configurable nginx log levels:** Allow the log level of the nginx processes to be configurable (`nginx.error_log_level`). ([2b0c8ac](https://github.com/NREL/api-umbrella/commit/2b0c8acf857d0654783218690c1d5fd5ab5c7735))
- **Configurable log levels for nginx rate limiting:** Allow the log level used for nginx rate limit messages to be configurable (`router.global_rate_limits.ip_connections_log_level` and `router.global_rate_limits.ip_rate_log_level`, [a804e0c](https://github.com/NREL/api-umbrella/commit/a804e0cab6cb83221d48072b4494fea0aad22c94))
- **Docker development environment:** Add a Docker-based development environment for easier development setup.
- **Experimental support for integrating automatic SSL certificate registration:** Integrate [lua-resty-auto-ssl](https://github.com/GUI/lua-resty-auto-ssl) for automatically handling SSL certificates. ([2f6c5b5](https://github.com/NREL/api-umbrella/commit/2f6c5b5805a5b50075c02478223f9a3c2ad1171b))

### Changed

- **Route API backend requests directly from Traffic Server:** Routing to API backends has been simplified so it occurs directly from Traffic Server, instead of routing back through an extra nginx hop. This should improve efficiency, simplifies routing, and eliminates DNS-related code. ([#410](https://github.com/NREL/api-umbrella/pull/410))
- **Admin UI Upgrades:** Upgrade the admin UI project from Ember 2.8 to Ember 3.9 and Bootstrap 3 to Bootstrap 4. This switch also moves all dependencies into NPM instead of Bower, and better uses ES6 syntax throughout the admin UI code. Integration tests have also been switched from PhantomJS to Selenium tests using headless Chrome. ([#429](https://github.com/NREL/api-umbrella/pull/429), [api.data.gov#434](https://github.com/18F/api.data.gov/issues/434))
- **Bootstrap upgrade:** Bootstrap upgrade for admin UI project from Bootstrap version 4 to 5.3 (02/2026)
- **Upgrade to GeoIP2 database:** The legacy GeoIP data previously being used has been discontinued, so GeoIP2 is now being used for geo-locating IP addresses. ([8f17dae](https://github.com/NREL/api-umbrella/commit/8f17dae991de7553cb67ee319392bf53c17a5083), [#440](https://github.com/NREL/api-umbrella/issues/440))
- **Redirect all website content to HTTPS by default:** All website requests now redirect to HTTPS by default. ([b3a8abc](https://github.com/NREL/api-umbrella/commit/b3a8abc81347cbeb274e00f40fcfccea3af1b546), [#407](https://github.com/NREL/api-umbrella/issues/407), [api.data.gov#430](https://github.com/18F/api.data.gov/issues/430))
- **Improve HTTPS requirements for API requests to error earlier:** When making an insecure API request, return an error about HTTPS being required before the API key requirement error. ([api.data.gov#454](https://github.com/18F/api.data.gov/issues/454))
- **Improve filesystem permissions and use more restrictive umask:** Ensure that the files generated by API Umbrella are only readable by the needed users, and not readable by other users that may have access to the server. ([2e595ce](https://github.com/NREL/api-umbrella/commit/2e595cec2dd748af2638f37e6729b7525f0e3572))
- **Increase size of allowed HTTP response header lengths:** If an API backend returned very long HTTP headers, it could generate 502 errors. This increases the default size of allowed HTTP headers, and also makes this length configurable. ([api.data.gov#461](https://github.com/18F/api.data.gov/issues/461), [#398](https://github.com/NREL/api-umbrella/issues/398))
- **Improve the build process for better caching:** The build process has been revamped to allow for better caching of the dependencies. ([#409](https://github.com/NREL/api-umbrella/pull/409)) https://github.com/NREL/api-umbrella/pull/414
- **Output Traffic Server logs as text logs:** Output Traffic Server's access log as a text log file, instead of a binary log. ([bd7f9fa](https://github.com/NREL/api-umbrella/commit/bd7f9fafb4c0345a37fa7428b6055c73744c3b4e))
- **Preload Lua modules in nginx to improve memory usage:** Lua modules are now preloaded in the nginx master process to improve memory usage by the nginx workers. ([031620a](https://github.com/NREL/api-umbrella/commit/031620a2022886cff1f57a70052d4c84fe34adf3))
- **Add more validations on API user names:** Add additional validations to ensure a valid first and last name have been entered to help prevent signup spam.
- **Improve Cache-Control responses for admin content:** Use stricter Cache-Control settings for admin responses that should not be cached, and improve caching of asset files. ([api.data.gov#425](https://github.com/18F/api.data.gov/issues/425))
- **Disable animations of admin analytics charts:** Disable the animations of the charts in the admin analytics to improve responsiveness. ([92c9351](https://github.com/NREL/api-umbrella/commit/92c9351ae99f2ebce961f31e8c33de40e8764d62))
- **Switch to Lua code for generating request IDs:**  Switch from ngx_txid to [lua-resty-txid](https://github.com/GUI/lua-resty-txid) for generating the request IDs to reduce need for custom nginx modules. ([9d2ebd4](https://github.com/NREL/api-umbrella/commit/9d2ebd475058b3505b236a52d4d3a6f06a9ae722))
- **Require multi-factor authentication for MAX.gov admin logins:** If using MAX.gov for admin logins, multi-factor authentication is required by default. ([api.data.gov#435](https://github.com/18F/api.data.gov/issues/435))
- **Upgrade bundled software dependencies:**
  - Elasticsearch 2.4.5 -\> 2.4.6
  - MongoDB 3.2.15 -\> 3.2.22
  - OpenResty 1.11.2.4 -\> 1.13.6.2
  - OpenSSL 1.0.2l -\> 1.0.2r
  - Rails 4.2.9 -\> 4.2.11.1
  - Rsyslog 8.27.0 -\> 8.1904.0
  - Ruby 2.3.4 -\> 2.4.6
  - Traffic Server 5.3.2 -\> 8.0.3

### Removed
- **Removed Ubuntu 12.04, Ubuntu 14.014 and Debian 7 packages:** Removed packages for unsupported distributions.
- **Removed references to request_ip_location:** Removed defunct references to the analytics `request_ip_location` field that was removed in v0.14.0. ([c783e1c](https://github.com/NREL/api-umbrella/commit/c783e1c47658af628a11893282c5040d30638dc9))
- **Removed experimental analytics:** Removed code related to experimental analytics backend. ([77d50d0](https://github.com/NREL/api-umbrella/commit/77d50d00397d7b7d00c50fbb3dca9ed2b8a55335))
- **Removed Vagrant development environment:** Removed the Vagrant-based development environment in favor of the Docker-based development environment.

## 0.15.0 (Unreleased)

Due to some packaging issues, version 0.15.0 was never released. See [version 0.15.1](#0150-2019-05-14).

## 0.14.4 (2017-07-15)

This update contains one important fix for v0.14.3. Upgrading is recommended if you are currently running v0.14.3.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Fixed

- **Rollback rsyslog to fix memory leak:** The version of rsyslog included in API Umbrella v0.14.3 (rsyslog v8.28.0) has a memory leak with the way API Umbrella configures it. This leads to rsyslog's memory use growing indefinitely. To fix this, the included version of rsyslog has been downgraded to v8.27.0 (and a bug report has been filed with rsyslog). ([api.data.gov#395](https://github.com/18F/api.data.gov/issues/395))

## 0.14.3 (2017-07-13)

This update contains a few bug fixes and some potential security fixes. Upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Changed

- **Make web-app timeouts configurable:** Timeouts in the Rails web application are now configurable. ([bfe3f06](https://github.com/NREL/api-umbrella/commit/bfe3f06b53a1444aa346962e47d13b90782b87a3))
- **On admin sign in with Google, prompt for specific account:** When the admin tool is configured to use Google for logins, always prompt for which Google account to use. ([c11ea16](https://github.com/NREL/api-umbrella/commit/c11ea1666a0b0287e1764ed031e42342a987e795))
- **Search behavior in admin APIs:** The free-form text search functionality provided by most of the admin APIs has been tweaked slightly. Now searching for an ID requires a full match instead of a partial match, and the "admins" API endpoint no longer searches the authentication token field. ([e936932](https://github.com/NREL/api-umbrella/commit/e936932bfce1c42b7c10b8c9e391f0d0b66e54c3), [aac482e](https://github.com/NREL/api-umbrella/commit/aac482e4c931e5de4d639a6cc5e94c11348d064c))
- **Upgrade bundled software dependencies:**
  - MongoDB 3.2.13 -\> 3.2.15
  - OpenResty 1.11.2.3 -\> 1.11.2.4 (security update: [CVE-2017-7529](http://mailman.nginx.org/pipermail/nginx-announce/2017/000200.html))
  - Rsyslog 8.27.0 -\> 8.28.0

### Fixed

- **Fix logrotation inside Docker container:** Log files could grow unbounded in size inside the API Umbrella Docker container. ([#365](https://github.com/NREL/api-umbrella/issues/365))
- **Fix the default "contact us" form:** A regression in v0.14.0 broke the default contact form's ability to send e-mails. ([api.data.gov#390](https://github.com/18F/api.data.gov/issues/390))
- **Fix logging data to authenticated Elasticsearch:** If using a custom Elasticsearch instance that uses HTTP basic authentication, this should work now. ([eae9553](https://github.com/NREL/api-umbrella/commit/eae95531b7b262cd59e9ecd8947079eaae5163d6))
- **Fix an internal analytics endpoint:** A regression in v0.14.0 broke a non-public API endpoint for summary analytics. ([api.data.gov#387](https://github.com/18F/api.data.gov/issues/387))

### Security

- **Fix admin password hashes exposure:**
  - If you use the local authentication mechanism for logging into the admin (new in v0.14.0 and the default), then upgrading to API Umbrella v0.14.3 is highly recommended.
  - If you rely only on external login providers (Google, GitHub, etc), then this issue should *not* affect your installation.
  - This issue could lead to the password hashes for admins being exposed to other admin users. Similarly, hashed password reset tokens or account unlock tokens could also be exposed to other admin users.
  - No plain text passwords or tokens would have been exposed, and these hashes would have only been exposed to other API Umbrella admin users. So the likelihood of this information being exploitable is hopefully very low (the hashes are considered strong and not easy to brute force), but upgrading is recommended to remedy this. You'll also want to weigh the risks for your installation, but it would be prudent to instruct your admins to resets their password.
  - Hash details: The exposed password hashes would have been hashed using bcrypt (with a cost factor of 11), and the exposed reset/unlock tokens would have been hashed using HMAC-256 (with the key being a random 128 character string, or the `web.rails_secret_token` value if you manually set that in your config). ([82dfe06](https://github.com/NREL/api-umbrella/commit/82dfe0641d0b43e2a634bbc8a1a820a78c93721d))
- **Updated bundled dependencies:**
  - OpenResty to 1.11.2.4 ([CVE-2017-7529](http://mailman.nginx.org/pipermail/nginx-announce/2017/000200.html))

## 0.14.2 (2017-05-26)

This update contains a few bug fixes. Upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Changed

- **Upgrade bundled software dependencies:**
  - Elasticsearch 2.4.4 -\> 2.4.5
  - MongoDB 3.2.12 -\> 3.2.13
  - Rsyslog 8.26.0 -\> 8.27.0

### Fixed

- **Fix removing last item from array fields in admin:** A regression in v0.14.0 prevented admins from removing the last items in certain array fields in the admin (for example, removing all roles from a user or API). ([#367](https://github.com/NREL/api-umbrella/issues/367))
- **Fix SSL validation against external Elasticsearch database:** Allow for explicit configuration of SSL settings when connecting to an external Elasticsearch database that is using HTTPS. Thanks to [@martinzuern](https://github.com/martinzuern). ([#364](https://github.com/NREL/api-umbrella/issues/364))
- **Increase default memory storge for configuration data**: Increase the default memory allocated for storing the live API backend configuration data from 600KB to 3MB to prevent potential issues when publishing lots of API backends. ([api.data.gov#385](https://github.com/18F/api.data.gov/issues/385))

## 0.14.1 (2017-04-23)

This update contains a few bug fixes and one potential security fix. Upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Changed

- **Upgrade bundled software dependencies:**
  - OpenResty 1.11.2.2 -\> 1.11.2.3
  - Ruby 2.3.3 -\> 2.3.4
  - Rsyslog 8.24.0 -\> 8.26.0

### Fixed

- **Missing validations on API backends:** It was possible to create API backends that omitted fields that should have been required in the Sub-URL Request Settings and Advanced Requests Rewriting sections. This could cause errors in loading the API configuration. ([#360](https://github.com/NREL/api-umbrella/issues/360))
- **Creating new admin groups:** Creating new admin groups in the admin was broken in v0.14.0. ([#347](https://github.com/NREL/api-umbrella/issues/347))
- **Outgoing example URL in admin:** In the API backend form of the admin, the example outgoing URL was incorrect in v0.14.0. ([b4ce3e28](https://github.com/NREL/api-umbrella/commit/b4ce3e28e77859c05b1989342cc8f0ce6fe85a06))
- **Ember.js deprecation warnings:** Fix some deprecation warnings in the admin tool. ([3e019140](https://github.com/NREL/api-umbrella/commit/3e0191409c1b24db3733b04d450de904b1492389), [27bf988d](https://github.com/NREL/api-umbrella/commit/27bf988d5b7c6f5d9bc1e6e8ef22f22a67e84064))

### Security

- **Don't pass admin session cookie to API backends:** The session cookie the API Umbrella admin uses is now stripped from requests to API backends. ([89371149](https://github.com/NREL/api-umbrella/commit/89371149585c1c94d1420bd8ce190a6fcdadb59b))

## 0.14.0 (2017-02-22)

This update focuses on upgrading various internal components of API Umbrella. It also offers new features and various bug fixes. A few potential security issues are also addressed. Upgrading is recommended, but there are some potential compatibility issues to note. See the Upgrade Instructions section below.

Many thanks to everyone that contributed with pull requests and bug reports!

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

This version has a few potential compatibility issues, depending on your setup, so be sure to read the following upgrade notes:

- **Database network binds:** For security reasons, Elasticsearch and MongoDB only listen for local connections now. If you have a multi-server setup, you'll need to [adjust the bind addresses](https://api-umbrella.readthedocs.io/en/latest/server/multi-server.html#bind-address). If you cannot upgrade to API Umbrella v0.14.0 immediately, you should check your current bind addresses to ensure they're secure.
- **Elasticsearch and MongoDB upgrades:**
  - The default version of Elasticsearch bundled with API Umbrella has been updated from 1.7 to 2.3.
  - The default version of MongoDB bundled with API Umbrella has been updated from 3.0 to 3.2.
  - If you're running a single server, all that should be required is a full restart (`sudo /etc/init.d/api-umbrella restart`).
  - If you're running a cluster of multiple database servers, then you may need to be more careful about the sequence of upgrades. See [Elasticsearch's upgrade notes](https://www.elastic.co/guide/en/elasticsearch/reference/2.3/restart-upgrade.html) and [MongoDB's upgrade notes](https://docs.mongodb.com/manual/release-notes/3.2-upgrade/) for more details.
  - The data API Umbrella stores in Elasticsearch should be compatible with the upgrade without further steps. However, if you store non-API Umbrella data in the same Elasticsearch server, you may want to check for data compatibility issues with the [elasticsearch-migration plugin](https://github.com/elastic/elasticsearch-migration/tree/1.x).
- **Admin login changes:** API Umbrella now defaults to using local login accounts for the accessing the admin (instead of using external login providers like Google, or GitHub). If you'd still like to use external login providers, they will need to be [explicitly enabled](https://api-umbrella.readthedocs.io/en/latest/server/admin-auth.html).

### Added

- **Local admin accounts:** There is now ([\#332](https://github.com/NREL/api-umbrella/pull/332), [\#314](https://github.com/NREL/api-umbrella/issues/314), [\#207](https://github.com/NREL/api-umbrella/issues/207), [\#247](https://github.com/NREL/api-umbrella/issues/247), [\#124](https://github.com/NREL/api-umbrella/issues/124), [\#45](https://github.com/NREL/api-umbrella/issues/45))
- **Default Elasticsearch query timeout:** For admin analytics queries, there's now a default timeout for the queries to try and prevent complex queries from running indefinitely. ([6b1187d3](https://github.com/NREL/api-umbrella/commit/6b1187d311f9fc17dcc7d8323ac82a6d2ec149a3))
- **Log API backend IDs:** Add logging of the matched API backend ID to the analytics database. [\#252](https://github.com/NREL/api-umbrella/issues/252)
- **Add GitLab login provider:** GitLab as been added as an external login provider. ([\#311](https://github.com/NREL/api-umbrella/issues/311))
- **Add security-related HTTP headers:**  Default `X-XSS-Protection`, `X-Frame-Options`, and `X-Content-Type-Options` headers have been added to website backend and web-app responses. ([f15ac873](https://github.com/NREL/api-umbrella/commit/f15ac87304aa233f94d96d794d1126ef4eb41d51))
- **Log rsyslog statistics:** Log additional statistics on rsyslog's queue size and processing information. ([c3afad9f](https://github.com/NREL/api-umbrella/commit/c3afad9faa7b9713d7aff8280c3904a4fe395691))
- **Redirect to admin URLs after login:** Deep links to areas in the admin are now retained throughout the login process. ([\#257](https://github.com/NREL/api-umbrella/issues/257))
- **Allow overriding the public HTTP/HTTPS ports:** When placing a load balancer in front of API Umbrella, allow for additional configuration to override the public ports. ([\#329](https://github.com/NREL/api-umbrella/issues/329), [\#296](https://github.com/NREL/api-umbrella/issues/296))
- **MongoDB WiredTiger storage support:** API Umbrella is now compatible with the newer MongoDB WiredTiger storage engine. ([\#260](https://github.com/NREL/api-umbrella/issues/260), [\#312](https://github.com/NREL/api-umbrella/pull/312))
- **MongoDB SCRAM-SHA-1 authentication support:** API Umbrella is now compatible with the default authentication mechanism in MongoDB 3.0+.  ([\#260](https://github.com/NREL/api-umbrella/issues/260), [\#312](https://github.com/NREL/api-umbrella/pull/312))

### Changed

- **Rails 4.2:** The internal `web-app` component (that provides the admin APIs) has been upgraded from Rails 3.2 to Rails 4.2. ([\#259](https://github.com/NREL/api-umbrella/issues/259))
- **Ember 2.8:** The internal `admin-ui` component (that provides the admin user interface) has been upgraded from Ember 1.7 to Ember 2.8. It has also been separate from the Rails codebase to be a standalone Ember app. ([\#257](https://github.com/NREL/api-umbrella/issues/257))
- **Bootstrap 3:** The admin user interface has been upgraded from using Bootstrap 2 to Bootstrap 3. ([\#258](https://github.com/NREL/api-umbrella/issues/258))
- **Elasticsearch 2.3:** The bundled version of Elasticsearch has been upgraded from Elasticsearch 1.7 to Elasticsearch 2.3. ([\#315](https://github.com/NREL/api-umbrella/pull/315), [\#261](https://github.com/NREL/api-umbrella/issues/261))
- **MongoDB 3.2:** The bundled version of MongoDB has been upgraded from MongoDB 3.0 to MongoDB 3.2. ([\#260](https://github.com/NREL/api-umbrella/issues/260))
- **ECharts for admin charts:** The admin interface has switched to use ECharts for its charts and maps. ([\#333](https://github.com/NREL/api-umbrella/pull/333), [\#124](https://github.com/NREL/api-umbrella/issues/124))
- More debugging details in nginx logs [\#334](https://github.com/NREL/api-umbrella/pull/334)
- **Unified test suite:** API Umbrella's internal test suite has been cleaned up, unified, and made more stable. ([\#305](https://github.com/NREL/api-umbrella/issues/305))
- **Disable X-Fowarded-Host parsing:** When determining which API backend to match, don't parse the `X-Forwarded-Host` header by default. ([api.data.gov#355](https://github.com/18F/api.data.gov/issues/355))
- **Quiet duplicative nginx error logging:** Don't log duplicate nginx errors to nginx's error log. ([3f90e158](https://github.com/NREL/api-umbrella/commit/3f90e1589619bc4f893c1aaafe26bacd78a1a48a))
- **Disable elasticsearch heapdumps:** If Elasticsearch runs out of memory, don't perform a heapdump by default. ([api.data.gov#351](https://github.com/18F/api.data.gov/issues/351))
- **Relative dates for admin analytics URLs:** Links to analytics URLs in the admin for the "last 30 days" will always reflect the last 30 days from the current date (rather than when the link was generated). [api.data.gov#73](https://github.com/18F/api.data.gov/issues/73)
- **Quicker process stops:** Allow API Umbrella to stop more quickly by changing how delayed-job terminates. ([837ca8f1](https://github.com/NREL/api-umbrella/commit/837ca8f1f344528add7060101d1e8c4cd575d2a9))
- **Upgrade bundled software dependencies:**
  - Elasticsearch 1.7.5 -\> 2.4.4
  - MongoDB 3.0.12 -\> 3.2.12
  - OpenResty 1.9.15.1 -\> 1.11.2.2
  - OpenSSL 1.0.2h -\> 1.0.2k
  - Ruby 2.2.5 -\> 2.3.3
  - Rsyslog 8.14.0 -\> 8.24.0

### Removed

- **Don't log website backend requests to analytics:** Requests to the website backend routes are no longer logged in the analytics database. [\#334](https://github.com/NREL/api-umbrella/pull/334)
- **Don't log unused fields to analytics database:** Several fields were being logged to the analytics database that API Umbrella was not using. These fields are no longer being logged to simplify things and reduce space. The fields no longer being stored are: `backend_response_time`, `internal_gatekeeper_time`, `proxy_overhead`, `request_ip_location`, and `request_query`. ([\#334](https://github.com/NREL/api-umbrella/pull/334))
- **Removed Mozilla Persona login option:** The Mozilla Persona service was shutdown, so it's no longer a valid long option for the admin. ([\#313](https://github.com/NREL/api-umbrella/issues/313), [\#323](https://github.com/NREL/api-umbrella/issues/323))
- **Removed non-functional HTTPS redirect options:** In the API Backends administration there were some "redirect" options for the "HTTPS Requirements" setting. These redirect options stopped working in API Umbrella v0.9.0. ([8d986169](https://github.com/NREL/api-umbrella/commit/8d986169b5a5bcd204419ea9b173ac737d0a8232))
- **Removed code for upgrading from API Umbrella v0.8:** Code for directly upgrading from API Umbrella v0.8 packages has been removed. ([101ac1e3](https://github.com/NREL/api-umbrella/commit/101ac1e390394329a496477876b6530c8c951428))

### Fixed

- **Missing analytics in Docker:** If running API Umbrella from the default Docker container, analytics information was missing. ([\#284](https://github.com/NREL/api-umbrella/issues/284), [\#327](https://github.com/NREL/api-umbrella/issues/327), [\#328](https://github.com/NREL/api-umbrella/pull/328))
- **LDAP authentication:** The LDAP login provider for the admin was broken. ([\#316](https://github.com/NREL/api-umbrella/issues/316), [\#278](https://github.com/NREL/api-umbrella/issues/278))
- **Startup race condition:** There was a race condition on API Umbrella's first startup that could lead to the database not being properly seeded. ([\#300](https://github.com/NREL/api-umbrella/issues/300), [f8495f11](https://github.com/NREL/api-umbrella/commit/f8495f11bb6a244deaaff6d1be6e683359903a00))
- **Corrupt rsyslog/request.log.gz file:** Rsyslog's `request.log.gz` log file could become correct (although this file isn't currently used). ([\#324](https://github.com/NREL/api-umbrella/issues/324))
- **Running Docker container from directory with spaces:** If you were running the API Umbrella Docker container from a directory containing spaces, it would error. ([\#322](https://github.com/NREL/api-umbrella/pull/322))
- **Improve MongoDB replicaset failover:** If using a MongoDB replicaset, improve the resiliency during a replicaset primary change.  ([89903486](https://github.com/NREL/api-umbrella/commit/89903486cfa1228bff38b1109ac0df599bd545c3))
- **Mixed up admin locale data:** In the admin, there was a possibility of locale data being mixed up across different users. ([2a98714a](https://github.com/NREL/api-umbrella/commit/2a98714a4ff76bb0f83c19fdaeefe7c503745520))
- **Missing analytics logs in certain cases:** Certain URLs with duplicate URL query parameters could fail to be logged in the analytics database in certain cases. [api.data.gov#358](https://github.com/18F/api.data.gov/issues/358)
- **Temp files in Docker container:** Fix generation of many geoip-auto-updater files in Docker container. ([\#290](https://github.com/NREL/api-umbrella/issues/290))
- **Missing package dependencies:** Add missing dependencies for the packages on minimal containers. ([\#290](https://github.com/NREL/api-umbrella/issues/290), [\#292](https://github.com/NREL/api-umbrella/pull/292), [\#328](https://github.com/NREL/api-umbrella/pull/328), [4a269133 ](https://github.com/NREL/api-umbrella/commit/4a2691338db1ee24f937a1dc32c1819b4958ae42))
- **Prevent double analytics requests in admin:** Sometimes 2 analytics requests would be made in the admin when loading an analytics page. ([\#257](https://github.com/NREL/api-umbrella/issues/257))
- **Proxying to SNI API backends:** Fix proxying to API backends that require SNI SSL support. ([api.data.gov#357](https://github.com/18F/api.data.gov/issues/357))
- **Overriding null values in api-umbrella.yml:** Fix overriding null values in the api-umbrella.yml config file. ([d8c5f743](https://github.com/NREL/api-umbrella/commit/d8c5f74377ae34b233ddcbd1f19fbef3220ef5d4), [\#278](https://github.com/NREL/api-umbrella/issues/278#issuecomment-238776123))
- **Intermittent test suite failures:** The reliability of the test suite has been improved. ([\#303](https://github.com/NREL/api-umbrella/issues/303))
- **Improve rsyslog queueing:** Fix the queue size settings for rsyslog. ([c3afad9f](https://github.com/NREL/api-umbrella/commit/c3afad9faa7b9713d7aff8280c3904a4fe395691))
- **Admin analytics timezones:** Fix timezone handling for dates in the admin date pickers. ([90ed2b62](https://github.com/NREL/api-umbrella/commit/90ed2b621fe7a331151ce826e62e828e4cbcdbee))
- **localhost DNS failures:** Fix startup issues if "localhost" possibly fails to resolve. ([\#212](https://github.com/NREL/api-umbrella/issues/212))
- **Log rotation issues:** The perpd log files weren't being rotated properly, and other log files could have rotation problems if API Umbrella was running as a non-default user. ([4d28e1e3](https://github.com/NREL/api-umbrella/commit/4d28e1e389811db86738b4df2463940dab8d5012))
- **Email verification with GitHub and Facebook:** If using GitHub or Facebook login providers for the admin, fix some issues with how verified emails are identified. ([d4e6fc5f](https://github.com/NREL/api-umbrella/commit/d4e6fc5ff2acd0f0e789639e3117e9a233eab4e6))
- **Ensure clean Ruby environment:** Ensure system-wide Ruby or Bundler installations don't conflict with API Umbrella's embedded version of Ruby. ([7d9208ca](https://github.com/NREL/api-umbrella/commit/7d9208caf6a1aa25d6ed10a6a95330dcb0a9bc1e))

### Security

- **Database network binds:** For security reasons, Elasticsearch and MongoDB only listen for local connections now. If you have a multi-server setup, you'll need to [adjust the bind addresses](https://api-umbrella.readthedocs.io/en/latest/server/multi-server.html#bind-address). If you cannot upgrade to API Umbrella v0.14.0 immediately, you should check your current bind addresses to ensure they're secure. ([\#287](https://github.com/NREL/api-umbrella/issues/287))
- **XSS in signup form:** Fix possible cross-site-scripting issue in the default signup form. ([api-umbrella-static-site#486950b1](https://github.com/NREL/api-umbrella-static-site/commit/486950b17db1b71ca71e624dbfb073f4a47ff379))
- **Admin group permissions:** If a limited admin knew the random UUID for another admin group, they could add admins to that group, despite not necessarily having permissions. ([c5ca3c1f](https://github.com/NREL/api-umbrella/commit/c5ca3c1f16829be77d71d55de57add0ae948ecc9))

## 0.13.0 (2016-07-30)

This update fixes one security issue and one small bug fix. Upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Security

- **Removed the configuration import/export tool from the admin:** This import/export tool could have presented a security issue if admin accounts with limited privilege scopes existed. These less-privileged admins could have viewed all API backend configuration, including API backends outside of their scoped permissions (however, they would not have been able to change the API backend configuration). Since the import/export tool has not been maintained and has other bugs, it has been removed entirely. If you still have a need for this tool, please [let us know](http://github.com/NREL/api-umbrella/issues/new). ([#272](https://github.com/NREL/api-umbrella/issues/272))

### Fixed

- **Don't show the "Beta Analytics" checkbox by default:** In the admin analytics interface, a "Beta Analytics" checkbox appeared in v0.12, but this should only be shown if the experimental Hadoop/Kylin-based analytics is actually enabled. ([c606261](https://github.com/NREL/api-umbrella/commit/c6062613380329b4cbd0ddfa4598e123e5908920))

## 0.12.0 (2016-06-30)

This update brings a variety of fixes and new features. A few potential security issues are also addressed. Upgrading is recommended.

Special thanks to [@ThibautGery](https://github.com/ThibautGery) and [@shaliko](https://github.com/shaliko) for their contributions to this release, and to anyone else reporting issues!

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

**Compatibility Notes:** There are two small changes in how the raw analytics data is stored in v0.12.0. This should only be relevant if you were querying the Elasticsearch analytics database directly (not via the admin UI or APIs) and interacting with the `request_at` or `request_query` fields. See the "Changed" section below for more details. Otherwise, v0.12.0 should be fully backwards compatible.

### Added

- **E-mail notification to admins on new API key signups:** You may optionally notify specified e-mail addresses whenever users signup for an API key. ([#246](https://github.com/NREL/api-umbrella/pull/246), [@ThibautGery](https://github.com/ThibautGery))
- **Elasticsearch 2 compatibility**: API Umbrella continues to bundle Elasticsearch 1.7 as the default version, but it now offers compatibility with external Elasticsearch 2 instances. ([#253](https://github.com/NREL/api-umbrella/pull/253), [@ThibautGery](https://github.com/ThibautGery))
- **Allow limited admins to create new groups or sub-scopes:** Non-superuser admins now may create more groups or other API scopes underneath their current permissions. ([#238](https://github.com/NREL/api-umbrella/pull/238), [api.data.gov#135](https://github.com/18F/api.data.gov/issues/135), [api.data.gov#339](https://github.com/18F/api.data.gov/issues/339))
- **Improve navigation of admin accounts in the admin interface:** When viewing or editing Admin Groups, the members of each admin group are displayed. ([api.data.gov#256](https://github.com/18F/api.data.gov/issues/256))
- **Ubuntu 16.04 Packages:** Binary packages are now available for Ubuntu 16.04. ([09f8f3c](https://github.com/NREL/api-umbrella/commit/09f8f3c))
- **Run web-app tests in Docker:** The test suite for the web-app component may be run with Docker. ([#243](https://github.com/NREL/api-umbrella/pull/243), [@ThibautGery](https://github.com/ThibautGery))
- **Experimental support of Hadoop/Kylin-based analytics:** Initial support has been added to optionally store the analytics data in Hadoop and query from Kylin. This offers an alternative to Elasticsearch for analytics that can scale to larger capacities in a more efficient manner. ([#227](https://github.com/NREL/api-umbrella/pull/227), [api.data.gov#235](https://github.com/18F/api.data.gov/issues/235))

### Changed

- **Analytics timestamps now reflect the ending time of the request:** The `request_at` timestamp logged in the analytics database now reports the time the request ended, rather than when the request began. ([#251](https://github.com/NREL/api-umbrella/pull/251))
- **Analytics fields no longer contain dots:** To prepare for Elasticsearch 2 upgrades, the `request_query` field in Elasticsearch may no longer contain dots/periods. ([#253](https://github.com/NREL/api-umbrella/pull/253))
- **Better SSL defaults and more configurable settings:** If using API Umbrella for SSL, the default SSL settings are now better. The defaults can also now be customized via the API Umbrella configuration file. ([#240](https://github.com/NREL/api-umbrella/pull/240), [@shaliko](https://github.com/shaliko))
- **Switch internal log collecting process:** The internal process used for buffering and transmitting log data for analytics storage has been switched from Heka to rsyslog. ([#227](https://github.com/NREL/api-umbrella/pull/227))
- **Switch to CMake based builds:** For better maintainability of the build process, CMake is now used. ([#226](https://github.com/NREL/api-umbrella/pull/226))
- **Linting changes for shell scripts:** Shell scripts used throughout the project now have a more consistent style, and any issues around variable quoting should be fixed. ([#237](https://github.com/NREL/api-umbrella/pull/237))
- **Upgrade bundled software dependencies:**
  - Elasticsearch 1.7.4 -> 1.7.5
  - MongoDB 3.0.8 -> 3.0.12
  - OpenResty 1.9.7.4 -> 1.9.15.1 (Security updates: CVE-2016-4450)
  - Ruby 2.2.4 -> 2.2.5

### Fixed

- **Fix admin searches involving special characters:** If using the search tools in the admin, searching for special characters did not behave as expected. ([api.data.gov#334](https://github.com/18F/api.data.gov/issues/334))
- **Fix "unexpected error" message when publishing with empty selection:** If you tried to publish API Backend changes without selecting any changes to publish, you received an "unexpected error" message. ([api.data.gov#307](https://github.com/18F/api.data.gov/issues/307))
- **Fix listing of website backends being visible to all admins:** Non-superuser admin accounts could view the complete listing of Website Backends in the database, even if they did not have permission to edit the website backend. ([api.data.gov#261](https://github.com/18F/api.data.gov/issues/261))
- **Fix running feature tests on non-English computers:** Some browser integration tests in the web-app component would fail if running the tests from a non-English computer ([#242](https://github.com/NREL/api-umbrella/issues/242))
- **Fix potential load conflicts if system has other Lua libraries install:** If the system running API Umbrella also has other Lua libraries installed into system-wide locations, potential conflicts could occur when API Umbrella tried to load its own dependencies. ([#250](https://github.com/NREL/api-umbrella/issues/250))
- **Fix potential for negative TTLs when distributing rate limit info:** If API Umbrella is operating in a cluster, unexpected negative TTLs could be calculated when distributing rate limit information among the servers in the cluster. ([api.data.gov#335](https://github.com/18F/api.data.gov/issues/335))
- **Fix the GeoIP data updater downloading too frequently on restarts:** If API Umbrella was manually restarted, the GeoIP data could be re-downloaded with more frequency than needed ([38d4654](https://github.com/NREL/api-umbrella/commit/38d4654))
- **Fix running tests in NodeJS v0.10.42+:** Some UTF-8 integration tests would fail if running the integration test suite in NodeJS v0.10.42 or higher. ([2a329ad](https://github.com/NREL/api-umbrella/commit/2a329ad))

### Security

- **Fix potential security issue if limited admins had knowledge of internal record UUIDs:** If non-superuser admins knew the random UUIDs for records they did not have permissions to, they could potentially overwrite the records. ([#238](https://github.com/NREL/api-umbrella/pull/238))
- **Fix possibility of admins abusing regex searches:** Admins could search for regular expressions, allowing for regular expression denial of service. ([api.data.gov#334](https://github.com/18F/api.data.gov/issues/334))
- **Fix listing of website backends being visible to all admins:** Non-superuser admin accounts could view the complete listing of Website Backends in the database, even if they did not have permission to edit the website backend. ([api.data.gov#261](https://github.com/18F/api.data.gov/issues/261))
- **Updated bundled dependencies:**
  - OpenResty to 1.9.15.1 ([CVE-2016-4450](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2016-4450))
  - nokogiri to 1.6.8 ([CVE-2015-8806](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2015-8806))

## 0.11.1 (2016-04-14)

This is a small update that fixes a couple bugs (one important one if you use the HTTP cache), makes a couple small tweaks, and updates some dependencies for security purposes. Upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Changed

- **Upgrade bundled software dependencies:**
  - OpenResty 1.9.7.1 -> 1.9.7.4 (Security updates: CVE-2016-0742, CVE-2016-0746, and CVE-2016-0747)
  - Rails 3.2.22 -> 3.2.22.2 (Security updates: CVE-2015-7576, CVE-2016-0751, CVE-2015-7577, CVE-2016-0752, CVE-2016-0753, CVE-2015-7581, CVE-2016-2097, and CVE-2016-2098)
  - Rebuild Mora and Heka with Go 1.5.4 (Security update: CVE-2016-3959)
- **Remove empty "Dashboard" link from the admin:** The "Dashboard" link has never had any content, so we've removed it from the admin navigation. ([api.data.gov#323](https://github.com/18F/api.data.gov/issues/323))
- **Make the optional public metrics API more configurable:** If enabled, the public metrics API's filters are now more easily configurable. ([api.data.gov#313](https://github.com/18F/api.data.gov/issues/313))

### Fixed

- **Resolve possible HTTP cache conflicts:** If API Umbrella is configured with multiple API backends that utilize the same frontend host and same backend URL path prefix, then if either API backend returned cacheable responses, then it's possible the responses would get mixed up. Upgrading is highly recommended if you utilize the HTTP cache and have multiple API backends utilizing the same URL path prefix. ([api.data.gov#322](https://github.com/18F/api.data.gov/issues/322))
- **Don't require API key roles for accessing admin APIs if admin token is used:** If accessing the administrative APIs using an admin authentication token, then the API key no longer needs any special roles assigned. This was a regression that ocurred in API Umbrella v0.9.0. ([#217](https://github.com/NREL/api-umbrella/issues/217))
- **Fix potential mail security issue:** OSVDB-131677.

## 0.11.0 (2016-01-20)

This is a small update that fixes a few bugs, adds a couple small new features, and updates some dependencies for security purposes. Upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` package using your package manager.

### Added

- **Search user role names in admin user search:** In the admin search interface for users, role names assigned to users are now searched too. ([api.data.gov#302](https://github.com/18F/api.data.gov/issues/302))
- **Allow for nginx's `server_names_hash_bucket_size` option to be set:** If you've explicitly defined `hosts` in the API Umbrella config with longer hostnames, you can now adjust the `nginx.server_names_hash_bucket_size` setting in `/etc/api-umbrella/api-umbrella.yml` to accommodate longer hostnames. ([#208](https://github.com/NREL/api-umbrella/issues/208))
- **Documentation on MongoDB authentication:** Add [documentation](http://api-umbrella.readthedocs.org/en/latest/server/db-config.html#mongodb-authentication) on configuring API Umbrella to use a MongoDB server with authentication.  ([#206](https://github.com/NREL/api-umbrella/issues/206))

### Changed

- **Upgrade bundled software dependencies:**
  - Elasticsearch 1.7.3 -> 1.7.4
  - MongoDB 3.0.7 -> 3.0.8
  - OpenResty 1.9.3.2 -> 1.9.7.1
  - Ruby 2.2.3 -> 2.2.4

### Fixed

- **Fix editing users with custom rate limits:** There were a few bugs related to editing custom rate limits on users that broke in the v0.9 release. ([api.data.gov#303](https://github.com/18F/api.data.gov/issues/303), [api.data.gov#304](https://github.com/18F/api.data.gov/issues/304), [api.data.gov#306](https://github.com/18F/api.data.gov/issues/306))
- **Fix MongoDB connections when additional options are given:** If the `mongodb.url` setting contained additional query string options, it could cause connection failures. ([#206](https://github.com/NREL/api-umbrella/issues/206))
- **Fix logging requests containing multiple `User-Agent` headers:** If a request contained multiple `User-Agent` HTTP headers, the request would fail to be logged to the analytics database. ([api.data.gov#309](https://github.com/18F/api.data.gov/issues/309))
- **Raise default resource limits when starting processes:** Restore functionality that went missing in the v0.9 release that raised the `nofile` and `noproc` resource limits to a configurable number.

### Security

We've updated several dependencies with reported security issues. We're not aware of these security issues impacting API Umbrella in any significant way, but upgrading is still recommended.

- Update bundled Ruby to 2.2.4 ([CVE-2015-7551](https://www.ruby-lang.org/en/news/2015/12/16/unsafe-tainted-string-usage-in-fiddle-and-dl-cve-2015-7551/))
- Recompiled Go dependencies with Go 1.5.3 ([CVE-2015-8618](https://groups.google.com/forum/#!topic/golang-announce/MEATuOi_ei4))
- Updated Gem dependencies with reported vulnerabilities:
  - jquery-rails ([CVE-2015-1840](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2015-1840))
  - mail ([OSVDB-131677](http://rubysec.com/advisories/OSVDB-131677/))
  - net-ldap ([OSVDB-106108](http://osvdb.org/show/osvdb/106108))
  - nokogiri ([CVE-2015-5312](https://web.nvd.nist.gov/view/vuln/detail?vulnId=CVE-2015-5312), [CVE-2015-7499](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2015-7499))

## 0.10.0 (2015-12-15)

This is a small update that fixes a few bugs and adds a couple small new features.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you may upgrade the `api-umbrella` using your package manager.

### Added

- **Make additional fields visible in the admin analytics:** The HTTP referer, Origin header, user agent family, and user agent type fields are now visible in analytics views for individual requests. ([#201](https://github.com/NREL/api-umbrella/issues/201))
- **Show version number in admin:** In the admin footer, the current API Umbrella version number is now displayed. ([#169](https://github.com/NREL/api-umbrella/issues/169))

### Fixed

- **Fixes to packages:** Various fixes and improvements to the `.rpm` and `.deb` packages to allow for easier package upgrades. ([#200](https://github.com/NREL/api-umbrella/issues/200))
- **Fix CSV downloads of admin analytics reports:** The CSV downloads of the Filter Logs results in the analytics admin was broken in the v0.9 release ([api.data.gov#298](https://github.com/18F/api.data.gov/issues/298))
- **Fix admin issues with admin groups and roles:** Admin groups management and role auto-completion were both broken in the v0.9 release ([api.data.gov#299](https://github.com/18F/api.data.gov/issues/299))
- **Better service start/stop error handling:** Better error messages if the trying to start the service when already started or stop the service when already stopped. ([#203](https://github.com/NREL/api-umbrella/issues/203))

## 0.9.0 (2015-11-27)

This is a significant upgrade to API Umbrella's internals, but should be backwards compatible with previous installations. It should be faster, more efficient, and more resilient, so upgrading is recommended.

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you must first stop API Umbrella manually (`sudo /etc/init.d/api-umbrella stop`) before installing the new package.

### Highlights

- **Internal rewrite:** The core API Umbrella proxy functionality has been rewritten in Lua embedded inside nginx. This simplifies the codebase, brings better performance, and reduces system requirements. (See [#86](https://github.com/NREL/api-umbrella/issues/86) and [#183](https://github.com/NREL/api-umbrella/pull/183))
- **Improved analytics logging:** Analytics logging is now faster. If a backlog occurs in logging requests, memory usage no longer grows. (See [api.data.gov#233](https://github.com/18F/api.data.gov/issues/233))
- **Resiliency:** API Umbrella caches some data locally so it can continue to operate even if the databases behind the scenes temporarily fail. (See [#183](https://github.com/NREL/api-umbrella/pull/183))
- **CLI improvements:** The `api-umbrella` CLI tool should be better behaved at starting and stopping all the processes as expected. Reloads should always pickup config file changes (See [#183](https://github.com/NREL/api-umbrella/pull/183) and [api.data.gov#221](https://github.com/18F/api.data.gov/issues/221))
- **Packaging improvements:** Binary packages are now available via apt or yum repos for easier installation (See [#183](https://github.com/NREL/api-umbrella/pull/183))
- **DNS and keep-alive improvements:** How API Umbrella detects DNS changes in backend hosts has been simplified and improved. This should allow for better keep-alive connection support. (See [#183](https://github.com/NREL/api-umbrella/pull/183))

### Everything Else

- **Fix bug causing 404s after publishing API backends:** If a default host was not set, publishing new API backends could make the admin inaccessible. (See [#192](https://github.com/NREL/api-umbrella/issues/192) and [#193](https://github.com/NREL/api-umbrella/issues/193))
- **Add concept of API key accounts with verified e-mail addresses:** APIs can now choose to restrict access to only API keys that have verified e-mail addresses. (See [api.data.gov#225](https://github.com/18F/api.data.gov/issues/225))
- **Fix initial admin accounts missing API token:** The initial superuser accounts created via the config file did not have a token for making admin API requests. (See [#95](https://github.com/NREL/api-umbrella/issues/95) and [#135](https://github.com/NREL/api-umbrella/issues/135))
- **Support wildcard frontend/backend hostnames:** API Backends can be configured with wildcard hostnames. (See [api.data.gov#240](https://github.com/18F/api.data.gov/issues/240))
- **Allow admins to view full API keys:** Superuser admin accounts can now view full API keys in the admin tool. (See [api.data.gov#276](https://github.com/18F/api.data.gov/issues/276))
- **Log why API Umbrella rejects requests in the analytics:** In the analytics screens, now you can see why API Umbrella rejected a request (for example, over rate limit, invalid API key, etc). (See [api.data.gov#226](https://github.com/18F/api.data.gov/issues/226))
- **Add missing delete actions to admin items:** Add the ability to delete admins, admin groups, api scopes, and website backends. (See [#134](https://github.com/NREL/api-umbrella/issues/134) and [#152](https://github.com/NREL/api-umbrella/issues/152))
- **Fix bug when invalid YAML entered into backend config:** If invalid YAML was entered into the API backend config, it could cause the API to go down. (See [#153](https://github.com/NREL/api-umbrella/issues/153))
- **Add CSV download for all admin accounts:** The entire list of admin accounts can be downloaded in a CSV. (See [api.data.gov#182](https://github.com/18F/api.data.gov/issues/182))
- **Per domain rate limits:** If API Umbrella is serving multiple domains, it now defaults to keeping rate limits for each domain separate. (See [api-umbrella-gatekeeper#19](https://github.com/NREL/api-umbrella-gatekeeper/pull/19))
- **Allow for longer hostnames:** Longer hostnames can now be used with API frontends. (See [#168](https://github.com/NREL/api-umbrella/issues/168))
- **Fix API Drilldown not respecting time zone:** In the analytics system, the API Drilldown chart wasn't using the user's timezone like the other analytics charts. (See [api.data.gov#217](https://github.com/18F/api.data.gov/issues/217))
- **Add optional LDAP authentication for admin:** The admin can now be configured to use LDAP. (See [#131](https://github.com/NREL/api-umbrella/issues/131))
- **Allow for system-wide IP or user agent blocks:** IPs or user agents can now be configured to be blocked at the server level. (See [api.data.gov#220](https://github.com/18F/api.data.gov/issues/220))
- **Allow for system-wide redirects:** HTTP redirects can now be configured at the server level. (See [api.data.gov#239](https://github.com/18F/api.data.gov/issues/239))
- **Log metadata about registration origins:** If the signup form is being used across different domains, the origin of the signup is now logged. (See [api.data.gov#218](https://github.com/18F/api.data.gov/issues/218))
- **Fix handling of unexpected `format` param:** If the `format` was of an unexpected type, it could cause issues when returning an error response. (See [api.data.gov#223](https://github.com/18F/api.data.gov/issues/223))
- **Fix handling of unexpected `Authorization` header:** If the `Authorization` header was of an unexpected type, it could cause the request to fail. (See [api.data.gov#266](https://github.com/18F/api.data.gov/issues/266))
- **Fix null selector options in analytics query builder:** In the analytics query builder, the "is null" or "is not null" options did not work properly. (See [api.data.gov#230](https://github.com/18F/api.data.gov/issues/230))
- **Analytics views now default to exclude over rate limit requests:** In the analytics screens, over rate limit requests are no longer displayed by default (but can still be viewed if needed). (See [api.data.gov#241](https://github.com/18F/api.data.gov/issues/241))
- **Fix admin account creation in Firefox:** Creating new admin accounts was not functioning in Firefox. (See [api.data.gov#271](https://github.com/18F/api.data.gov/issues/271))
- **Allow for response caching when `Authorization` header is passed:** If the `Authorization` header is part of the API backend configuration, caching of these responses is now allowed. (See [api.data.gov#281](https://github.com/18F/api.data.gov/issues/281))
- **Allow for easier customization of contact URLs:** Custom contact URLs are now easier to set for individual API backends (See [api.data.gov#285](https://github.com/18F/api.data.gov/issues/285))

## 0.8.0 (2015-04-26)

This update fixes a couple of security issues and a few important bugs. It's highly recommended anyone running earlier versions upgrade to v0.8.0.

[Download 0.8.0 Packages](http://nrel.github.io/api-umbrella/download/)

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you must first stop API Umbrella manually (`sudo /etc/init.d/api-umbrella stop`) before installing the new package.

### Hightlights

- **Fix cross-site-scripting vulnerability:** In the admin, there was a possibility of a cross-site-scripting vulnerability. (See [api.data.gov#214](https://github.com/18F/api.data.gov/issues/214))
- **Make it easier to route to new website pages:** Any non-API request will be routed to the website backend, making it easier to manage your public website content. In addition, different website content can now be served up for different hostnames. (See [api.data.gov#146](https://github.com/18F/api.data.gov/issues/146) and [#69](https://github.com/NREL/api-umbrella/issues/69))
- **New analytics querying interface:** The new interface for querying the analytics allows you to filter your analytics using drop down menus and form fields. This should be much easier to use than the raw Lucene queries we previously relied on. (See [#15](https://github.com/NREL/api-umbrella/issues/15) and [api.data.gov#168](https://github.com/18F/api.data.gov/issues/168))
- **Add ability to set API response headers:** This feature can be used to set headers on the API responses, which can be used to force CORS headers with API Umbrella. (See [#81](https://github.com/NREL/api-umbrella/issues/81) and [api.data.gov#188](https://github.com/18F/api.data.gov/issues/188))
- **Add feature to specify HTTPS requirements:** This feature can be used force HTTPS usage to access your APIs and can also be used to help transition new users to HTTPS-only. (See [api.data.gov#34](https://github.com/18F/api.data.gov/issues/34))
- **Allow for better customization of the API key signup confirmation e-mail:** The contents for the API key signup e-mail can now be better tailored for different sites. (See [api.data.gov#133](https://github.com/18F/api.data.gov/issues/133))
- **Fix file descriptor leak:** This could lead to an outage by exhausting your systems maximum number of file descriptors for setups with lots of API backends using domains with short-lived TTLs. (See [api.data.gov#188](https://github.com/18F/api.data.gov/issues/188))

### Everything Else

- **Fix possibility of very brief 503 errors:** For setups with lots of API backends using domains with short-lived TTLs, there was a possibility of rare 503 errors when DNS changes were being reloaded. (See [api.data.gov#207](https://github.com/18F/api.data.gov/issues/207))
- **Fix server log rotation issues:** There were a few issues present with a default installation that prevented log files from rotating properly, and may have wiped previous log files each night. This should now be resolved. (See [api.data.gov#189](https://github.com/18F/api.data.gov/issues/189))
- **Fix couple of edge-cases where custom rate limits weren't applied:** There were a couple of edge-cases in how API backends and users were configured that could lead to rate limits being ignored. (See [#127](https://github.com/NREL/api-umbrella/issues/127), [api.data.gov#201](https://github.com/18F/api.data.gov/issues/201), [api.data.gov#202](https://github.com/18F/api.data.gov/issues/202))
- **Fix situations where analytics may have not been logged for specific queries:** If a URL contained UTF-8 character or if a query parameter contained a date or time, there were certain situations where that request would fail to be logged in the analytics database. (See [api.data.gov#198](https://github.com/18F/api.data.gov/issues/198) and [api.data.gov#213](https://github.com/18F/api.data.gov/issues/213))
- **Fix proxy transforming backslashes into forward slashes in the URL:** If a URL contained a backslash character, it may have been transformed into a forward slash when the API backend received the request. (See [api.data.gov#199](https://github.com/18F/api.data.gov/issues/199))
- **Gracefully handle MongoDB replicaset changes:** API Umbrella should continue to serve requests with no downtime if the MongoDB primary server changes. (See [api.data.gov#200](https://github.com/18F/api.data.gov/issues/200))
- **Add registration source information to admin user list:** The user registration source is now shown in the user listing and can also be searched by the free-from search field. (See [api.data.gov#190](https://github.com/18F/api.data.gov/issues/190))
- **Fix broken pagination on the admin list of API backends:** The list of API backends didn't properly handle pagination when more than 50 backends were present. (See [api.data.gov#209](https://github.com/18F/api.data.gov/issues/209))
- **Fixes to URL encoding for advanced request rewriting:** If you were doing complex URL rewriting with "Route Pattern" rewrites under the Advanced Request Rewriting section, this fixes a variety of URL encoding issues.
- **Reduce duplicative nginx reloads for DNS changes:** If your system has several API backends with domains that have short-lived TTLs, there were a couple race conditions that could lead to nginx reloading twice on DNS changes. This is now fixed so the unnecessary, duplicate reload commands are gone. (See [api.data.gov#191](https://github.com/18F/api.data.gov/issues/191))
- **Fix incorrectly logging HTTPS requests as HTTP:** API Umbrella v0.7 introduced a bug the led to HTTPS requests being logged as HTTP requests in the analytics database. (See [api.data.gov#208](https://github.com/18F/api.data.gov/issues/208))
- **Fix analytics charts during daylight saving time:** During daylight saving time, the daily analytics charts in the admin may have contained an extra duplicate day with 0 results. (See [api.data.gov#147](https://github.com/18F/api.data.gov/issues/147))
- **Prevent all URL prefixes from being removed from API backends:** In the admin, it was possible to remove all URL prefixes from an API backend's configuration, leaving it in an invalid state (See [api.data.gov#215](https://github.com/18F/api.data.gov/issues/215))
- **Improve compatibility of install on systems with other Rubies present:** If you're installing API Umbrella on a system that already had something like rbenv/rvm/chruby installed, this should should fix some compatibility issues.
- **Build process improvements:** Various improvements to our build process for packaging new binary releases.
- **Upgrade bundled dependencies:**
  - Bundler 1.7.12 -> 1.7.14
  - ElasticSearch 1.4.2 -> 1.5.1
  - MongoDB 2.6.7 -> 2.6.9
  - nginx 1.7.9 -> 1.7.10
  - ngx_headers_more 0.25 -> 0.26
  - ngx_txid a41a705 -> f1c197c
  - Node.js 0.10.36 -> 0.10.38
  - OpenSSL 1.0.1l -> 1.0.1m
  - Ruby 2.1.5 -> 2.1.6
  - RubyGems 2.4.5 -> 2.4.6
  - Varnish 4.0.2 -> 4.0.3

## 0.7.1 / 2015-02-11

This update fixes a couple of important bugs that were discovered shortly after rolling out the v0.7.0 release. It's highly recommended anyone running v0.7.0 upgrade to v0.7.1.

[Download 0.7.1 Packages](http://nrel.github.io/api-umbrella/download/)

### Upgrade Instructions

If you're upgrading a previous API Umbrella version, you must first stop API Umbrella manually (`sudo /etc/init.d/api-umbrella stop`) before installing the new package.

### Changes

- Fix 502 Bad Gateway errors for newly published API backends. Due to the DNS changes introduced in v0.7.0, newly published API backends may have not have properly resolved and passed traffic to the backend servers. (See [#107](https://github.com/NREL/api-umbrella/issues/107))
- Fix broken admin for non-English web browsers. The translations we introduced in v0.7.0 should actually now work (whoops!). (See [#103](https://github.com/NREL/api-umbrella/issues/103))
- Cut down on unnecessary DNS changes triggering reloads.
- Adjust internal API Umbrella logging to reduce error and warning log messages for expected events.
- Disables Groovy scripting in default ElasticSearch setup due to [CVE-2015-1427](http://www.elasticsearch.org/blog/elasticsearch-1-4-3-and-1-3-8-released/).

## 0.7.0 / 2015-02-08

[Download 0.7.0 Packages](http://nrel.github.io/api-umbrella/download/)

### Upgrade Instructions

If you're upgrading from API Umbrella v0.6.0, you must first stop API Umbrella manually (`sudo /etc/init.d/api-umbrella stop`) before installing the new package.

### Highlights

- **Admin UI Improvements:** Lots of tweaks and fixes have been made to the various parts of the admin to make it easier to use. There are better defaults, better notifications, and a lot more error validations to make it easier to manage API backends and users. (Related: [api.data.gov#160](https://github.com/18F/api.data.gov/issues/160), [api.data.gov#158](https://github.com/18F/api.data.gov/issues/158), [#49](https://github.com/NREL/api-umbrella/issues/49))
- **Improved DNS handling for API backends:** Fixes edge-case scenarios where DNS lookups may have not refreshed too quickly for backend API domain names with short TTLs (typically affecting API backends hosted behind Heroku, Akamai, or an Amazon Elastic Load Balancer). In certain rare cases, this could have temporarily taken down an API. (Related: [api.data.gov#131](https://github.com/18F/api.data.gov/issues/131))
- **Improved analytics gathering:** Fixes edge-case scenarios where analytics logs may have not been gathered. Request logs should also now show up in the admin analytics more quickly (within a few seconds). (Related: [#37](https://github.com/NREL/api-umbrella/issues/37), [api.data.gov#138](https://github.com/18F/api.data.gov/issues/138), [api.data.gov#106](https://github.com/18F/api.data.gov/issues/106))
- **Improved server startup:** Lots of fixes for various startup issues that should make starting API Umbrella more reliable on all platforms. API Umbrella v0.6 was our first package release across multiple platforms, so thanks to everyone in the community for reporting issues, and apologies if things were a bit bumpy. Hopefully v0.7 should be a bit easier to get running for everyone, but please let us know if not. (Related: [#42](https://github.com/NREL/api-umbrella/issues/42), [#89](https://github.com/NREL/api-umbrella/issues/89), [#92](https://github.com/NREL/api-umbrella/issues/92), [#100](https://github.com/NREL/api-umbrella/issues/100)
- **Dyanmic HTTP header rewriting:** Thanks to [@darylrobbins](https://github.com/darylrobbins) for this new feature, you can now perform more complex header rewriting by referencing existing header values during the HTTP header rewriting phase. (Related: [#96](https://github.com/NREL/api-umbrella/issues/96), [api-umbrella-gatekeeper#7](https://github.com/NREL/api-umbrella-gatekeeper/pull/7))
- **Admin Internationalization:** We've begun work to allow the admin interface to be translated into other languages. This is still incomplete, but the main admin menus and a good portion of the API Backends screen should now be available in Finnish, French, Italian, and Russian (with some translations started in German and Spanish too). Many thanks to [@perfaram](https://github.com/perfaram), [@kyyberi](https://github.com/kyyberi), Vesa Härkönen, vpilo, and enizev! (Related: [#60](https://github.com/NREL/api-umbrella/issues/60))

### Everything Else

- Fix analytics CSV downloads. (Related: [api.data.gov#173](https://github.com/18F/api.data.gov/issues/173))
- Fix default API key signup form in IE8-9. (Related [api.data.gov#174](https://github.com/18F/api.data.gov/issues/174))
- Give a better error message to restricted admins when they try to create an API outside of their permission scope. (Related: [api.data.gov#152](https://github.com/18F/api.data.gov/issues/152))
- Improve the admin UI for publishing backend changes to provide more sane checkbox defaults. (Related: [api.data.gov#169](https://github.com/18F/api.data.gov/issues/169))
- Treat admin logins case insensitively. (Related [api.data.gov#170](https://github.com/18F/api.data.gov/issues/170))
- Fix bugs preventing the GitHub OAuth based logins for admins from working. (Related: [#46](https://github.com/NREL/api-umbrella/issues/46), [#88](https://github.com/NREL/api-umbrella/issues/88))
- Fix limited admin account not having privileges to assign the special "api-umbrella-key-creator" role. (Related: [api.data.gov#157](https://github.com/18F/api.data.gov/issues/157))
- Fix analytics permissions for restricted admins for API paths containing uppercase characters. (Related: [api.data.gov#154](https://github.com/18F/api.data.gov/issues/154))
- Fix admin permissions for API backends with multiple URL prefixes. (Related: [api.data.gov#156](https://github.com/18F/api.data.gov/issues/156))
- Increase the default number of concurrent HTTP connections the various processes can accept.
- Fix inability to unset referrer or IP restrictions on user accounts once set. (Related [#97](https://github.com/NREL/api-umbrella/issues/97), [api.data.gov#155](https://github.com/18F/api.data.gov/issues/155))
- Fix issues surrounding default log rotation setup
- Retry connections to MongoDB in the event of MongoDB disconnects.
- Add the ability to selectively reload API Umbrella components via the `api-umbrella reload` command.
- Add a [deployment process](http://nrel.github.io/api-umbrella/docs/deployment/) for deploying non-packaged updates for API Umbrella components directly from git. (Related: [api.data.gov#159](https://github.com/18F/api.data.gov/issues/159), [api.data.gov#161](https://github.com/18F/api.data.gov/issues/161), [#99](https://github.com/NREL/api-umbrella/issues/99))
- Upgrade bundled dependencies
  - Bundler 1.7.4 -> 1.7.12
  - ElasticSearch 1.3.4 -> 1.4.2
  - MongoDB 2.6.5 -> 2.6.7
  - nginx 1.7.6 -> 1.7.9
  - Node.js 0.10.33 -> 0.10.36
  - OpenSSL 1.0.1j -> 1.0.1l
  - Redis 2.8.17 -> 2.8.19
  - Ruby 2.1.3 -> 2.1.5
  - RubyGems 2.4.2 -> 2.4.5
  - Ruby on Rails 3.2.19 -> 3.2.21
  - Supervisor 3.1.2 -> 3.1.3

## 0.6.0 / 2014-10-27

- Initial package releases for CentOS, Debian, and Ubuntu.

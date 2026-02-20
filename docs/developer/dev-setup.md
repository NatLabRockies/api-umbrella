# Development Setup

The easiest way to get started with API Umbrella development is to use [Docker](https://www.docker.com) to setup a local development environment.

## Prerequisites

- 64bit CPU - the development VM requires an 64bit CPU on the host machine
- [Docker](https://www.docker.com/get-started)

## Setup

After installing Docker, follow these steps:

### Optional: Trusted local HTTPS with mkcert

By default, the development environment uses a self-signed SSL certificate, which requires accepting browser warnings and using `curl -k`. To use a locally-trusted certificate instead:

1. [Install mkcert](https://github.com/FiloSottile/mkcert#installation)
2. Run the setup script:

```sh
$ ./bin/setup
```

This generates trusted certificates in `dev/ssl/` and installs mkcert's root CA in your system trust store. You only need to do this once.

### Start the development environment

```sh
# Get the code and spinup your development VM
$ git clone https://github.com/NREL/api-umbrella.git
$ cd api-umbrella
$ docker compose up
```

Assuming all goes smoothly, you should be able to see the homepage at [https://localhost:8201/](https://localhost:8201/). If you ran `./bin/setup` with mkcert, you can access the site directly. Otherwise, you will need to accept the self-signed SSL certificate warning in your browser.

If you're having any difficulties getting the development environment setup, then open an [issue](https://github.com/NREL/api-umbrella/issues).

## Development Data

The development environment automatically seeds some sample data to help you get started quickly.

### Admin Account

The first time you visit the admin interface, you'll need to create an admin account:

1. Go to [https://localhost:8201/admin/](https://localhost:8201/admin/)
2. Accept the self-signed certificate warning in your browser
3. Since no admin accounts exist yet, you'll be automatically redirected to a signup page
4. Fill in the signup form:
   - **Email:** Enter any email address (e.g., `admin@example.com`)
   - **Password:** Choose a password (minimum 14 characters)
   - **Password Confirmation:** Re-enter the password
5. Click **"Sign up"** and you'll be logged in automatically

This first-time signup is only available when no admin accounts exist. Once you've created your admin account, subsequent admins can be added through the admin interface under **"Admins"** in the **"Admin Accounts"** menu.

### Demo API User

A demo API user is created with a known API key for testing:

- **Email:** `demo.developer@example.com`
- **API Key:** `DEMO_KEY_FOR_DEVELOPMENT_ONLY_1234567890`

### Demo API Backend

A sample API backend is created and published that proxies to [httpbin.org](https://httpbin.org), a useful service for testing HTTP requests:

- **Name:** HTTPBin Echo API (Dev)
- **Frontend Path:** `/echo/`
- **Backend:** `https://httpbin.org/`

### Testing the Proxy

You can test the full proxy flow using the demo API key and backend:

```sh
# Test the echo endpoint (returns request details as JSON)
$ curl -k "https://localhost:8201/echo/get?foo=bar" \
    -H "X-Api-Key: DEMO_KEY_FOR_DEVELOPMENT_ONLY_1234567890"

# Test POST requests
$ curl -k "https://localhost:8201/echo/post" \
    -H "X-Api-Key: DEMO_KEY_FOR_DEVELOPMENT_ONLY_1234567890" \
    -H "Content-Type: application/json" \
    -d '{"hello": "world"}'
```

The `-k` flag is needed to accept the self-signed SSL certificate (not needed if you used mkcert via `./bin/setup`).

### Sample Analytics Data

The development environment seeds sample API request logs so the analytics graphs have data to display. Approximately 60-150 log entries are created, spread across the past 30 days, simulating requests to the `/echo/` endpoints.

To view the analytics:

1. Log in to the admin interface at [https://localhost:8201/admin/](https://localhost:8201/admin/)
2. Go to **"Analytics"** → **"API Drilldown"** or **"Filter Logs"**
3. Select a date range that includes the past 30 days

The seeded data includes a mix of successful (200) and error (400/500) responses to demonstrate different analytics views.

## Directory Structure

A quick overview of some of the relevant directories for development:

- `src/api-umbrella/admin-ui`: The admin user interface which utilizes the administrative APIs provided by the web-app.
- `src/api-umbrella/cli`: The actions behind the `api-umbrella` command line tool.
- `src/api-umbrella/proxy`: The custom reverse proxy where API requests are validated before being allowed to the underlying API backend.
- `src/api-umbrella/web-app`: Provides the public and administrative APIs.
- `test`: Proxy tests and integration tests for the entire API Umbrella stack.

## Making Code Changes

This development environment runs the various components in "development" mode, which typically means any code changes you make will immediately be reflected. However, this does mean this development environment will run API Umbrella slower than in production.

While you can typically edit files and see your changes, for certain types of application changes, you may need to restart the server processes. There are two ways to restart things if needed:

```sh
# Quick: Reload most server processes by executing a reload command:
docker-compose exec app api-umbrella reload

# Slow: Fully restart everything:
docker-compose stop
docker-compose up
```

## Writing and Running Tests

See the [testing section](testing.html) for more information about writing and running tests.

# Development Setup

The easiest way to get started with API Umbrella development is to use [Docker](https://www.docker.com) to setup a local development environment.

## Prerequisites

- 64bit CPU - the development VM requires an 64bit CPU on the host machine
- [Docker](https://www.docker.com/get-started)

## Setup

After installing Docker, follow these steps:

```sh
# Get the code and spinup your development VM
$ git clone https://github.com/NREL/api-umbrella.git
$ cd api-umbrella
$ docker-compose up
```

Assuming all goes smoothly, you should be able to see the homepage at [https://localhost:8201/](https://localhost:8201/). You will need to accept the self-signed SSL certificate for localhost in order to access the development environment.

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

The `-k` flag is needed to accept the self-signed SSL certificate.

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

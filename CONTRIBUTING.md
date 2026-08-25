# Contributing to API Umbrella

Thank you for your interest in contributing to API Umbrella! This document outlines how to get involved, submit changes, and follow the project's standards.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Environment](#development-environment)
- [Project Structure](#project-structure)
- [Making Changes](#making-changes)
- [Running Tests](#running-tests)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

Please be respectful and constructive in all interactions. We ask contributors to be kind and considerate, in the spirit of the [Contributor Covenant](https://www.contributor-covenant.org/).

## Getting Started

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/api-umbrella.git
   cd api-umbrella
   ```
3. **Add the upstream remote:**
   ```bash
   git remote add upstream https://github.com/NREL/api-umbrella.git
   ```

## Development Environment

API Umbrella uses Docker for local development. Prerequisites:

- [Docker](https://docs.docker.com/get-docker/) (v20+)
- [Docker Compose](https://docs.docker.com/compose/) (v2+)

Start the full development stack:

```bash
docker compose up
# If you only have the legacy binary:
# docker-compose up
```

Refer to the [full development setup guide](https://api-umbrella.readthedocs.org/en/latest/developer/dev-setup.html) for detailed instructions.

## Project Structure

```
api-umbrella/
├── src/api-umbrella/
│   ├── proxy/          # Lua/OpenResty core request pipeline
│   ├── http-api/       # Lua/OpenResty internal HTTP API
│   ├── admin-ui/       # Ember.js admin dashboard (JavaScript)
│   ├── web-app/        # Lua/Lapis developer portal
│   ├── cli/            # Lua CLI management tools
│   └── bin/            # Rust binaries (envoy-config-wrapper)
├── docs/               # reStructuredText documentation
├── test/               # Ruby/Minitest integration test suite
├── docker/             # Docker entrypoints and config
├── tasks/              # Build task scripts
└── config/             # Default configuration files
```

## Making Changes

1. **Create a branch** from `master`:
   ```bash
   git checkout -b my-feature-or-fix
   ```
2. **Make your changes.** Keep commits small and focused.
3. **Follow the existing code style** for the language you are editing:
   - **Lua:** Follow the patterns used in `src/api-umbrella/proxy/` and `src/api-umbrella/http-api/`.
   - **JavaScript (Ember.js):** Run the linter before committing (`pnpm lint` inside `src/api-umbrella/admin-ui/`).
   - **Ruby (tests):** Run RuboCop (`bundle exec rubocop`) before committing.
   - **Rust:** Run `cargo fmt` and `cargo clippy` before committing.
4. **Write or update tests** for any changed behaviour.

## Running Tests

The integration test suite runs inside Docker:

```bash
# Run all tests
docker-compose run --rm app make test

# Run a specific test file
docker-compose run --rm app bundle exec minitest test/apis/v1/admins/test_create.rb
```

For JavaScript linting in the admin UI:

```bash
cd src/api-umbrella/admin-ui
pnpm install
pnpm lint
```

For Ruby linting:

```bash
bundle install
bundle exec rubocop
```

## Submitting a Pull Request

1. **Sync with upstream** before opening a PR:
   ```bash
   git fetch upstream
   git rebase upstream/master
   ```
2. **Push your branch** to your fork:
   ```bash
   git push origin my-feature-or-fix
   ```
3. **Open a Pull Request** against the `master` branch of `NREL/api-umbrella`.
4. Fill in the PR description explaining:
   - What problem this solves or what feature it adds.
   - How it was tested.
   - Any breaking changes.
5. A maintainer will review your PR. Please respond to feedback promptly.

## Reporting Issues

Found a bug? Have a feature request?

- Search [existing issues](https://github.com/NREL/api-umbrella/issues) first.
- If none exist, [open a new issue](https://github.com/NREL/api-umbrella/issues/new) with:
  - A clear title and description.
  - Steps to reproduce (for bugs).
  - API Umbrella version and OS/environment details.

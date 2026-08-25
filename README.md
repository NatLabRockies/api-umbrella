# 🕴️API Umbrella

# What Is API Umbrella?

API Umbrella is an open source API management platform for exposing web service APIs. The basic goal of API Umbrella is to make life easier for both API creators and API consumers. How?

* **Make life easier for API creators:** Allow API creators to focus on building APIs.
  * **Standardize the boring stuff:** APIs can assume the boring stuff (access control, rate limiting, analytics, etc.) is already taken care if the API is being accessed, so common functionality doesn't need to be implemented in the API code.
  * **Easy to add:** API Umbrella acts as a layer above your APIs, so your API code doesn't need to be modified to take advantage of the features provided.
  * **Scalability:** Make it easier to scale your APIs.
* **Make life easier for API consumers:** Let API consumers easily explore and use your APIs.
  * **Unify disparate APIs:** Present separate APIs as a cohesive offering to API consumers. APIs running on different servers or written in different programming languages can be exposed at a single endpoint for the API consumer.
  * **Standardize access:** All your APIs can be accessed using the same API key credentials.
  * **Standardize documentation:** All your APIs are documented in a single place and in a similar fashion.

## Table of Contents

- [Architecture](#architecture)
- [Dependencies](#dependencies)
- [Getting Started](#getting-started)
- [Development](#api-umbrella-development)
- [Who's Using API Umbrella?](#whos-using-api-umbrella)
- [Contributing](#contributing)
- [License](#license)

## Architecture

API Umbrella sits in front of your existing APIs as a reverse proxy layer. Incoming API requests flow through the following components:

```
Internet / API Consumer
        │
        ▼
┌───────────────────┐
│   Envoy Proxy     │  ← TLS termination, routing, load balancing
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  OpenResty / Lua  │  ← Request processing pipeline (rate limiting,
│  (HTTP API layer) │    auth, analytics, logging) — src/api-umbrella/proxy
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Your API Backend │  ← Your actual API service(s)
└───────────────────┘

Supporting services:
  ┌──────────────┐    ┌───────────────┐
  │  PostgreSQL  │    │  OpenSearch   │
  │  (config,    │    │  (analytics & │
  │   users,     │    │   log data)   │
  │   sessions)  │    └───────────────┘
  └──────────────┘

Admin & Developer interfaces:
  ┌───────────────────┐    ┌──────────────────────┐
  │  Admin UI         │    │  Web App             │
  │  (Ember.js SPA)   │    │  (Lua/OpenResty MVC) │
  │  src/.../admin-ui │    │  src/.../web-app     │
  └───────────────────┘    └──────────────────────┘
```

### Component Overview

| Component | Location | Language / Framework | Purpose |
|---|---|---|---|
| **Proxy** | `src/api-umbrella/proxy/` | Lua / OpenResty (nginx) | Core request pipeline: auth, rate limiting, logging |
| **HTTP API** | `src/api-umbrella/http-api/` | Lua / OpenResty | Internal API for config and health checks |
| **Admin UI** | `src/api-umbrella/admin-ui/` | Ember.js (JavaScript) | Web admin dashboard |
| **Web App** | `src/api-umbrella/web-app/` | Lua / Lapis | Developer portal and API key signup |
| **Envoy Config Wrapper** | `src/api-umbrella/bin/envoy-config-wrapper.rs` | Rust | Generates Envoy xDS configuration from PostgreSQL |
| **CLI** | `src/api-umbrella/cli/` | Lua | Command-line management interface |
| **GeoIP Updater** | `src/api-umbrella/geoip-auto-updater.lua` | Lua | Automatic GeoIP database updates |

### Component Dependency Graph (code-derived)

```mermaid
graph TD
  Client[API consumers] --> Envoy[Envoy proxy]
  Envoy --> Proxy[proxy (OpenResty/Lua)]
  Proxy --> Backend[Your API backends]
  AdminUI[admin-ui (Ember.js)] --> WebApp[web-app APIs]
  Proxy --> Postgres[(PostgreSQL)]
  WebApp --> Postgres
  Proxy --> OpenSearch[(OpenSearch)]
  WebApp --> OpenSearch
  EnvoyWrapper[envoy-config-wrapper (Rust)] --> Envoy
```

Code references used for the graph:

- `src/api-umbrella/admin-ui/app/models/api.js` and other `admin-ui` models call `/api-umbrella/v1/*` web-app endpoints.
- `src/api-umbrella/web-app/app.lua` and `src/api-umbrella/web-app/models/analytics_search_opensearch.lua` use PostgreSQL and OpenSearch utilities.
- `src/api-umbrella/proxy/startup/seed_database.lua` and `src/api-umbrella/proxy/startup/opensearch_setup.lua` use PostgreSQL and OpenSearch utilities.
- `src/api-umbrella/bin/envoy-config-wrapper.rs` writes Envoy config and execs the Envoy binary.

## Dependencies

### Runtime Services

| Service | Purpose |
|---|---|
| [OpenResty](https://openresty.org/) (nginx + LuaJIT) | Core reverse proxy and request processing |
| [Envoy Proxy](https://www.envoyproxy.io/) | Edge proxy for TLS termination and request routing |
| [PostgreSQL](https://www.postgresql.org/) | Primary database for configuration, users, and sessions |
| [OpenSearch](https://opensearch.org/) | Analytics and API log storage |

### Build-time / Tooling

| Tool | Purpose |
|---|---|
| [LuaRocks](https://luarocks.org/) | Lua package manager |
| [pnpm](https://pnpm.io/) | JavaScript package manager (admin-ui, web-app) |
| [Rust / Cargo](https://www.rust-lang.org/) | Build the Envoy config wrapper binary |
| [Docker](https://www.docker.com/) | Development and CI environment |

### Key Frontend Libraries (Admin UI)

| Library | Version | Purpose |
|---|---|---|
| [Ember.js](https://emberjs.com/) | ~4.x | Admin SPA framework |
| [Font Awesome](https://fontawesome.com/) | ^6.7 | Icons |

### Key Ruby Libraries (Test suite)

| Gem | Purpose |
|---|---|
| `minitest` | Test framework |
| `capybara` + `selenium-webdriver` | Browser integration tests |
| `activerecord` + `pg` | Database access in tests |
| `opensearch-ruby` | OpenSearch access in tests |
| `typhoeus` | HTTP client for API tests |
| `factory_bot` | Test data factories |

## Getting Started

Once you have API Umbrella up and running, there are a variety of things you can do to start using the platform. For a quick tutorial, see [getting started](https://api-umbrella.readthedocs.org/en/latest/getting-started.html).

### Quick Start with Docker

```bash
git clone https://github.com/NREL/api-umbrella.git
cd api-umbrella
docker compose up
# If you only have the legacy binary:
# docker-compose up
```

The application will be available at:
- **API / Proxy:** `http://localhost:8200`
- **Admin UI:** `http://localhost:8200/admin/`
- **Developer Portal:** `http://localhost:8200/signup/`

## API Umbrella Development

Are you interested in working on the code behind API Umbrella? See our [development setup guide](https://api-umbrella.readthedocs.org/en/latest/developer/dev-setup.html) to get a local development environment running.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting changes.

## Documentation

| Resource | Link |
|---|---|
| Getting Started | [readthedocs](https://api-umbrella.readthedocs.org/en/latest/getting-started.html) |
| Full Documentation | [readthedocs](https://api-umbrella.readthedocs.org/en/latest/) |
| Development Setup | [readthedocs](https://api-umbrella.readthedocs.org/en/latest/developer/dev-setup.html) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |
| Admin Docs | [docs/admin/](docs/admin/) |
| Server Configuration | [docs/server/](docs/server/) |
| API Consumer Docs | [docs/api-consumer/](docs/api-consumer/) |

## Who's Using API Umbrella?

* [api.data.gov](https://api.data.gov/)
* [NREL Developer Network](http://developer.nrel.gov/)
* [api.sam.gov](https://api.sam.gov)

Are you using API Umbrella? [Edit this file](https://github.com/NREL/api-umbrella/blob/master/README.md) and let us know.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to get started, the development workflow, and the code of conduct.

## License

API Umbrella is open sourced under the [MIT license](LICENSE.txt).

import "path"

#schema: {
  app_env: string | *"production"

  root_dir: string | *"/opt/api-umbrella" @tag(root_dir)
  etc_dir: string | *path.Join([root_dir, "etc"])
  var_dir: string | *path.Join([root_dir, "var"])
  log_dir: string | *path.Join([var_dir, "log"])
  run_dir: string | *path.Join([var_dir, "run"])
  tmp_dir: string | *path.Join([var_dir, "tmp"])
  db_dir: string | *path.Join([var_dir, "db"])
  _embedded_root_dir: string @tag(embedded_root_dir)
  "_embedded_root_dir": _embedded_root_dir
  "_src_root_dir": string @tag(src_root_dir)
  "_runtime_config_path": string | *path.Join([run_dir, "runtime_config.json"]) @tag(runtime_config_path)

  #service_name: "egress" | "router" | "web"
  _default_services: [...#service_name] & [
    "egress",
    "router",
    "web",
  ]
  services: [...#service_name] | *_default_services

  user: string | null | *"api-umbrella"
  group: string | null | *"api-umbrella"

  rlimits: {
    nofile: uint | *100000
    nproc: uint | *20000
  }

  http_port: uint16 | *80
  https_port: uint16 | *443

  secret_key?: string

  listen: {
    addresses: [...string] | *[
      "*",
      "[::]",
    ]
  }

  nginx: {
    workers: uint | *"auto"
    worker_connections: uint | *8192
    listen_so_keepalive: string | *"on"
    listen_backlog?: uint
    error_log_level: string | *"notice"
    access_log_filename: string | *"access.log"
    access_log_options: string | null | *"buffer=256k flush=10s"
    proxy_connect_timeout: uint | *30
    proxy_read_timeout: uint | *60
    proxy_send_timeout: uint | *60
    proxy_buffer_size: string | *"8k"
    proxy_buffers: string | *"8 8k"
    keepalive_timeout: uint | *75
    upstream_keepalive_connections_per_worker: uint | *10
    upstream_keepalive_idle_timeout: uint | *60
    ssl_protocols: string | *"TLSv1 TLSv1.1 TLSv1.2"
    ssl_ciphers: string | *"ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS"
    ssl_session_cache: string | *"shared:ssl_sessions:50m"
    ssl_session_timeout: string | *"24h"
    ssl_session_tickets: string | *"off"
    ssl_buffer_size: uint | *1400
    ssl_prefer_server_ciphers: string | *"on"
    ssl_ecdh_curve: string | *"secp384r1"
    variables_hash_max_size: uint | *2048
    server_names_hash_bucket_size?: uint
    lua_ssl_trusted_certificate?: string
    lua_ssl_verify_depth: uint | *5
    shared_dicts: {
      active_config: {
        size: string | *"3m"
      }
      active_config_locks: {
        size: string | *"128k"
      }
      active_config_ipc: {
        size: string | *"128k"
      }
      api_users: {
        size: string | *"3m"
      }
      api_users_misses: {
        size: string | *"2m"
      }
      api_users_locks: {
        size: string | *"256k"
      }
      api_users_ipc: {
        size: string | *"256k"
      }
      geocode_city_cache: {
        size: string | *"100k"
      }
      interval_locks: {
        size: string | *"20k"
      }
      jobs: {
        size: string | *"20k"
      }
      locks: {
        size: string | *"20k"
      }
      rate_limit_counters: {
        size: string | *"20m"
      }
      rate_limit_exceeded: {
        size: string | *"2m"
      }
      upstream_checksums: {
        size: string | *"200k"
      }
      discovery: {
        size: string | *"200k"
      }
      jwks: {
        size: string | *"200k"
      }
      introspection: {
        size: string | *"200k"
      }
    }
  }

  gatekeeper: {
    #api_key_method_name: "header" | "get_param" | "basic_auth_username"
    _default_api_key_methods: [...#api_key_method_name] & [
      "header",
      "get_param",
      "basic_auth_username",
    ]
    api_key_methods: [...#api_key_method_name] | *_default_api_key_methods
    api_key_cache: bool | *true
    api_key_min_length: uint | *4
    api_key_max_length: uint | *60
  }

  trafficserver: {
    host: string | *"127.0.0.1"
    port: uint16 | *14009
    storage: {
      size: string | *"256M"
    }
    records: {
      http: {
        keep_alive_no_activity_timeout_out: uint | *120
      }
      cache: {
        ram_cache: {
          size: string | *"-1"
        }
      }
      net: {
        connections_throttle: uint | *30000
        max_requests_in: uint | *0
        max_connections_in: uint | *30000
        default_inactivity_timeout: uint | *86400
      }
    }
  }

  envoy: {
    #scheme: "http" | "https"
    scheme: #scheme | *"http"
    host: string | *"127.0.0.1"
    port: uint16 | *14000
    listen: {
      host: string | *"127.0.0.1"
      port: uint16 | *14000
    }
    admin: {
      host: string | *"127.0.0.1"
      port: uint16 | *14001
      listen: {
        host: string | *"127.0.0.1"
        port: uint16 | *14001
      }
    }
    http_proxy: {
      enabled: bool | *false
      host: string | *"127.0.0.1"
      port: uint16 | *14002
      listen: {
        host: string | *"127.0.0.1"
        port: uint16 | *14002
      }
      allowed_domains: [...string] | *[]
    }
    smtp_proxy: {
      enabled: bool | *false
      host: string | *"127.0.0.1"
      port: uint16 | *14003
      listen: {
        host: string | *"127.0.0.1"
        port: uint16 | *14003
      }
      endpoint: {
        host?: string
        port?: uint16
      }
    }
    // Allow additional/all ciphers for API backends that may not support the
    // default set.
    tls_cipher_suites: [...string] | *[
      "ALL",
    ]
    // Allow additional cipher curves for some API backends that may not
    // support the defaults. https://github.com/envoyproxy/envoy/issues/21053
    tls_ecdh_curves: [...string] | *[
      "X25519",
      "P-256",
      "P-384",
      "P-521",
    ]
    tls_certificate: {
      certificate_chain?: string
      private_key?: string
      domain?: string
    }
    global_downstream_max_connections: uint16 | *32768
    cli_args?: string
  }

  envoy_control_plane: {
    host: string | *"127.0.0.1"
    port: uint16 | *14007
    listen: {
      host: string | *"127.0.0.1"
      port: uint16 | *14007
    }
    metrics_listen: {
      host: string | *"127.0.0.1"
      port: uint16 | *14008
    }
  }

  api_server: {
    host: string | *"127.0.0.1"
    port: uint16 | *14010
    listen: {
      host: string | *"127.0.0.1"
      port: uint16 | *14010
    }
  }

  web: {
    host: string | *"127.0.0.1"
    port: uint16 | *14012
    listen: {
      host: string | *"127.0.0.1"
      port: uint16 | *14012
    }
    request_timeout: uint | *30
    workers: uint | "auto" | *2
    worker_connections: uint | *8192
    listen_so_keepalive: string | *"on"
    listen_backlog?: uint
    error_log_level: string | *"notice"
    api_user: {
      email_regex: string | *"\\A[^@<>\\s]+@[^@<>\\s]+\\.[^@<>\\s]+\\z"
      first_name_exclude_regex: string | *"(http|https|www|<|>|\\r|\\n)"
      last_name_exclude_regex: string | *"(http|https|www|<|>|\\r|\\n)"
      force_public_verify_email: bool | *false
    }
    admin: {
      initial_superusers: [...string] | *[]
      username_is_email: bool | *true
      password_length_min: uint | *14
      password_length_max: uint | *72
      email_regex: string | *"\\A[^@<>\\s]+@[^@<>\\s]+\\.[^@<>\\s]+\\z"
      password_regex?: string
      login_header?: string
      login_footer?: string
      auth_strategies: {
        #auth_strategy_name: "cas" | "facebook" | "github" | "gitlab" | "google" | "ldap" | "local" | "login.gov" | "max.gov"
        _default_enabled: [...#auth_strategy_name] & [
          "local",
        ]
        enabled: [...#auth_strategy_name] | *_default_enabled
        cas: {
          options: {
            service_validate_url: string | *"/serviceValidate"
            login_url: string | *"/login"
            logout_url: string | *"/logout"
            ssl: bool | *true
          }
        }
        facebook: {
          client_id?: string
          client_secret?: string
        }
        github: {
          client_id?: string
          client_secret?: string
        }
        gitlab: {
          client_id?: string
          client_secret?: string
          discovery: string | *"https://gitlab.com/.well-known/openid-configuration"
          token_signing_alg_values_expected: string | *"RS256"
          token_endpoint_auth_method: string | *"client_secret_post"
          scope: string | *"openid email"
        }
        google: {
          client_id?: string
          client_secret?: string
          discovery: string | *"https://accounts.google.com/.well-known/openid-configuration"
          token_signing_alg_values_expected: string | *"RS256"
          token_endpoint_auth_method: string | *"client_secret_post"
          scope: string | *"openid email"
          authorization_params: {
            prompt: string | *"select_account"
          }
        }
        ldap: {
          options: {
            host?: string
            port: uint16 | *389
            method: string | *"plain"
            base?: string
            uid: string | *"sAMAccountName"
            bind_dn?: string
            password?: string
            title?: string
          }
        }
        "login.gov": {
          client_id?: string
          client_rsa_private_key?: string
          client_rsa_public_key?: string
          discovery: string | *"https://idp.int.identitysandbox.gov/.well-known/openid-configuration"
          token_signing_alg_values_expected: string | *"RS256"
          token_endpoint_auth_method: string | *"private_key_jwt"
          scope: string | *"openid email"
          redirect_after_logout_with_id_token_hint: bool | *false
          authorization_params: {
            acr_values: string | *"http://idmanagement.gov/ns/assurance/loa/1"
          }
        }
        "max.gov": {
          require_mfa: bool | *true
          options: {
            host: string | *"login.max.gov"
            login_url: string | *"/cas/login"
            service_validate_url: string | *"/cas/serviceValidate"
            logout_url: string | *"/cas/logout"
            ssl: bool | *true
          }
        }
      }
    }
    contact_form_email?: string
    contact: {
      email_regex: string | *"\\A[^@\\s]+@[^@\\s]+\\.[^@\\s]+\\z"
      name_exclude_regex: string | *"(http|https|www|<|>|\\r|\\n)"
      api_exclude_regex: string | *"(<script|\\r|\\n)"
      subject_exclude_regex: string | *"(<script|\\r|\\n)"
      message_exclude_regex: string | *"(\\A\\s*\\d+\\s*\\z)"
    }
    mailer: {
      smtp_settings: {
        address: string | *"127.0.0.1"
        port: uint16 | *25
        starttls?: bool
        ssl?: bool
        ssl_verify?: bool
        ssl_host?: string
        domain?: string
        authentication?: string
        user_name?: string
        password?: string
      }
      headers?: {...}
    }
    analytics_v0_summary_required_role: string | null | *"api-umbrella-public-metrics"
    analytics_v0_summary_start_time: string | *"2013-07-01T00:00:00.000Z"
    analytics_v0_summary_end_time?: string
    analytics_v0_summary_filter?: string
    analytics_v0_summary_db_timeout: uint | *900 // 15 minutes
    analytics_v0_summary_analytics_timeout: uint | *2400 // 40 minutes
    max_body_size: string | *"1m"
    allowed_signup_embed_urls_regex?: string
    default_host?: string
    send_notify_email?: bool
    admin_notify_email?: string
    #scheme: "http" | "https"
    recaptcha_scheme: #scheme | *"https"
    recaptcha_host: string | *"www.google.com"
    recaptcha_port: uint16 | *443
    recaptcha_v2_secret_key?: string
    recaptcha_v2_required: bool | *false
    recaptcha_v2_required_origin_regex?: string
    recaptcha_v3_secret_key?: string
    recaptcha_v3_required: bool | *false
    recaptcha_v3_required_score: float | *0.9
    recaptcha_v3_required_origin_regex?: string
  }

  static_site: {
    host: string | *"127.0.0.1"
    port: uint16 | *14013
    listen: {
      host: string | *"127.0.0.1"
      port: uint16 | *14013
    }
    build_dir: string | *path.Join([_embedded_root_dir, "app/build/dist/example-website"])
    api_key?: string
  }

  router: {
    api_backends: {
      keepalive_idle_timeout: uint | *120
      keepalive_connections_max_age: uint | *1800
    }
    trusted_proxies: [...string] | *[]
    global_rate_limits: {
      ip_rate?: string
      ip_burst?: uint
      ip_rate_size: string | *"8m"
      ip_rate_log_level: string | *"error"
      ip_connections?: uint
      ip_connections_size: string | *"5m"
      ip_connections_log_level: string | *"error"
    }
    web_app_host: string | *"*"
    website_backend_required_https_regex_default: string | *"^.*"
    redirect_not_found_to_https: bool | *true
    active_config: {
      refresh_local_cache_interval: uint | *1
    }
    api_backend_required_https_regex_default?: string
    match_x_forwarded_host?: bool
  }

  fluent_bit: {
    #on_off_bool: "on" | "off"

    host: string | *"127.0.0.1"
    port: uint16 | *14014
    service: {
      log_level: string | *"info"
      flush: float | *1
      storage_max_chunks_up: uint | *32
      storage_backlog_mem_limit: string | *"16M"
    }
    aws_access_key_id?: string
    aws_secret_access_key?: string
    outputs: {
      opensearch: {
        enabled: bool | *true
        aws_auth: #on_off_bool | *"off"
        aws_region?: string
        aws_service_name: string | *"es"
        retry_limit: uint | *30
        storage_total_limit_size: string | *"128M"
        trace_error: #on_off_bool | *"on"
        buffer_size: string | *"64KB"
      }

      s3: {
        enabled: bool | *false
        region?: string
        bucket?: string
        s3_key_format: string | *"/$TAG[1]/%Y/%m/%d/%Y%m%dT%H%M%SZ-$UUID.jsonl.gz"
        storage_class: string | *"STANDARD"
        compression: string | *"gzip"
        upload_chunk_size: string | *"30M"
        store_dir_limit_size: string | *"300M"
        total_file_size: string | *"250M"
        upload_timeout: string | *"60m"
        send_content_md5: bool | *true
        content_type: string | *"application/gzip"
        auto_retry_requests: bool | *true
        preserve_data_ordering: bool | *true
        retry_limit: uint | *5
      }
    }
  }

  log: {
    destination: string | *"file"
  }

  dns_resolver: {
    negative_ttl: uint | false | *60
    // This default could be revisited, but historically we didn't resolve AAAA
    // records for API backends, so for compatibility keep this disabled by
    // default. Enabling may also break certain hosting environments that still
    // aren't IPv6 compatible.
    allow_ipv6: bool | *false
    nameservers?: [...string]
  }

  postgresql: {
    host: string | *"postgres"
    port: uint16 | *5432
    database: string | *"api_umbrella"
    username: string | *"api_umbrella_app"
    password?: string
    ssl: bool | *false
    ssl_verify: bool | *false
    ssl_required: bool | *false
    connect_timeout: uint | *5000
    statement_timeout: uint | *30000
    migrations: {
      username: string | *"api_umbrella_owner"
      password?: string
    }
  }

  opensearch: {
    hosts: [...string] | *[
      "http://opensearch:9200",
    ]
    index_name_prefix: string | *"api-umbrella"
    template_version: uint | *4
    template: {
      index: {
        refresh_interval: string | *"5s"
        number_of_shards: uint | *3
        number_of_replicas: uint | *2
      }
      translog: {
        durability: string | *"async"
        sync_interval: string | *"10s"
      }
    }
    max_buckets: uint | *10000
  }

  #analytics_output_name: "opensearch"
  analytics: {
    adapter: #analytics_output_name | *"opensearch"
    timezone: string | *"UTC"
    log_request_url_query_params_separately: bool | *false

    _default_outputs:  [...#analytics_output_name] & [
      "opensearch"
    ]
    outputs: [...#analytics_output_name] | *_default_outputs
  }

  strip_cookies: [...string] | *[
    "^__utm.*$",
    "^_ga$",
    "^is_returning$",
  ]
  strip_response_cookies?: [...string]
  strip_server_header: bool | *false

  site_name: string | *"API Umbrella"

  #host: {
    hostname: string
    default: bool | *false
    http_strict_transport_security?: string
    real_ip_header?: string
    set_real_ip_from?: string
    real_ip_header?: string
    real_ip_recursive?: string
    ssl_cert?: string
    ssl_cert_key?: string
    rewrites?: [...string]
  }
  hosts: [...#host] | *[]

  _default_api_backend_settings_value: #api_backend_settings & {
    #require_https_value: "required_return_error" | "transition_return_error" | "optional"
    require_https: #require_https_value | *"required_return_error"
    _default_rate_limits: [...#api_backend_rate_limit]
    _default_rate_limits: [
      {
        duration: 1000
        limit_by: "ip"
        limit_to: 50
        distributed: false
      },
      {
        duration: 1000
        limit_by: "api_key"
        limit_to: 20
        distributed: false
      },
      {
        duration: 15000
        limit_by: "ip"
        limit_to: 250
        distributed: true
      },
      {
        duration: 15000
        limit_by: "api_key"
        limit_to: 150
        distributed: true
      },
      {
        duration: 3600000
        limit_by: "api_key"
        limit_to: 1000
        distributed: true
        response_headers: true
      },
    ]
    rate_limits: [...#api_backend_rate_limit] | *_default_rate_limits
    error_templates: {
      json: """
        {
          \"error\": {
            \"code\": {{code}},
            \"message\": {{message}}
          }
        }
        """

      xml: """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <response>
          <error>
            <code>{{code}}</code>
            <message>{{message}}</message>
          </error>
        </response>
        """

      csv: """
        Error Code,Error Message
        {{code}},{{message}}
        """

      html: """
        <html>
          <body>
            <h1>{{code}}</h1>
            <p>{{message}}</p>
          </body>
        </html>
        """
    }

    error_data: {
      common: {
        signup_url: "{{base_url}}"
        contact_url: "{{base_url}}/contact/"
      }
      not_found: {
        status_code: 404
        code: "NOT_FOUND"
        message: "The requested URL was not found on this server."
      }
      api_key_missing: {
        status_code: 403
        code: "API_KEY_MISSING"
        message: "No api_key was supplied. Get one at {{signup_url}}"
      }
      api_key_invalid: {
        status_code: 403
        code: "API_KEY_INVALID"
        message: "An invalid api_key was supplied. Get one at {{signup_url}}"
      }
      api_key_disabled: {
        status_code: 403
        code: "API_KEY_DISABLED"
        message: "The api_key supplied has been disabled. Contact us at {{contact_url}} for assistance"
      }
      api_key_unverified: {
        status_code: 403
        code: "API_KEY_UNVERIFIED"
        message: "The api_key supplied has not been verified yet. Please check your e-mail to verify the API key. Contact us at {{contact_url}} for assistance"
      }
      api_key_unauthorized: {
        status_code: 403
        code: "API_KEY_UNAUTHORIZED"
        message: "The api_key supplied is not authorized to access the given service. Contact us at {{contact_url}} for assistance"
      }
      over_rate_limit: {
        status_code: 429
        code: "OVER_RATE_LIMIT"
        message: "You have exceeded your rate limit. Try again later or contact us at {{contact_url}} for assistance"
      }
      internal_server_error: {
        status_code: 500
        code: "INTERNAL_SERVER_ERROR"
        message: "An unexpected error has occurred. Try again later or contact us at {{contact_url}} for assistance"
      }
      https_required: {
        status_code: 400
        code: "HTTPS_REQUIRED"
        message: "Requests must be made over HTTPS. Try accessing the API at: {{https_url}}"
      }
    }
  }
  default_api_backend_settings: #api_backend_settings | *_default_api_backend_settings_value

  #api_backend_server: {
    id?: string
    host: string
    port: uint16 | "{{api_server.port}}" | "{{web.port}}"
  }
  #api_backend_url_match: {
    id?: string
    frontend_prefix: string
    backend_prefix: string
    exact_match?: bool
  }
  #api_backend_rate_limit: {
    duration: uint
    limit_by: "ip" | "api_key"
    limit_to: uint
    distributed?: bool
    response_headers?: bool
  }
  #api_backend_header: {
    key: string
    value: string
  }
  #api_backend_settings: {
    require_https?: string
    disable_api_key?: bool
    rate_limit_mode?: string
    require_https?: string
    disable_analytics?: bool
    redirect_https?: bool
    rate_limits?: [...#api_backend_rate_limit]
    headers?: [...#api_backend_header]
    error_templates?: {
      json?: string,
      xml?: string,
      csv?: string,
      html?: string,
    }
    error_data?: {
      common?: {...}
      not_found?: {...}
      api_key_missing?: {...}
      api_key_invalid?: {...}
      api_key_disabled?: {...}
      api_key_unverified?: {...}
      api_key_unauthorized?: {...}
      over_rate_limit?: {...}
      internal_server_error?: {...}
      https_required?: {...}
    }
  }
  #api_backend_sub_settings: {
    http_method: string
    regex: string
    settings: #api_backend_settings
  }
  #api_backend: {
    id?: string
    name?: string
    frontend_host: string
    backend_host?: string
    backend_protocol?: string
    balance_algorithm?: string
    sort_order?: uint
    servers: [...#api_backend_server]
    url_matches: [...#api_backend_url_match]
    settings: #api_backend_settings
    sub_settings: [...#api_backend_sub_settings]
  }
  _default_internal_apis: [...#api_backend] & [
    {
      id: "api-umbrella-gatekeeper-backend"
      name: "API Umbrella - Gatekeeper APIs"
      frontend_host: "{{router.web_app_host}}"
      backend_protocol: "http"
      balance_algorithm: "least_conn"
      sort_order: 1
      servers: [{
        host: "{{api_server.host}}"
        port: "{{api_server.port}}"
      }]
      url_matches: [{
        frontend_prefix: "/api-umbrella/v1/health"
        backend_prefix: "/api-umbrella/v1/health"
      }, {
        frontend_prefix: "/api-umbrella/v1/state"
        backend_prefix: "/api-umbrella/v1/state"
      }, {
        frontend_prefix: "/api-umbrella/v0/nginx-status"
        backend_prefix: "/api-umbrella/v0/nginx-status"
      }, {
        frontend_prefix: "/api-umbrella/v0/shared-memory-stats"
        backend_prefix: "/api-umbrella/v0/shared-memory-stats"
      }]
      settings: {
        require_https: "required_return_error"
      }
      sub_settings: [{
        http_method: "get"
        regex: "^/api-umbrella/v1/(health|state)"
        settings: {
          disable_api_key: true
          rate_limit_mode: "unlimited"
          require_https: "optional"
          disable_analytics: true
        }
      }]
    },
    {
      id: "api-umbrella-web-app-backend"
      name: "API Umbrella - HTTP APIs"
      frontend_host: "{{router.web_app_host}}"
      backend_protocol: "http"
      balance_algorithm: "least_conn"
      sort_order: 2
      servers: [{
        host: "{{web.host}}"
        port: "{{web.port}}"
      }]
      url_matches: [{
        frontend_prefix: "/api-umbrella/"
        backend_prefix: "/api-umbrella/"
      }, {
        frontend_prefix: "/admins/"
        backend_prefix: "/admins/"
      }, {
        frontend_prefix: "/admins"
        backend_prefix: "/admins"
        exact_match: true
      }, {
        frontend_prefix: "/admin/"
        backend_prefix: "/admin/"
      }, {
        frontend_prefix: "/admin"
        backend_prefix: "/admin"
        exact_match: true
      }, {
        frontend_prefix: "/web-assets/"
        backend_prefix: "/web-assets/"
      }]
      settings: {
        require_https: "required_return_error"
      }
      sub_settings: [{
        http_method: "any"
        regex: "^/admin/stats"
        settings: {
          disable_api_key: true
        }
      }, {
        http_method: "POST"
        regex: "^/admin/login"
        settings: {
          disable_api_key: true
          rate_limit_mode: "custom"
          rate_limits: [{
            duration: 15000
            limit_by: "ip"
            limit_to: 100
            distributed: true
            response_headers: true
          }]
        }
      }, {
        http_method: "any"
        regex: "^/(admin|web-assets)"
        settings: {
          disable_api_key: true
          rate_limit_mode: "unlimited"
          redirect_https: true
          disable_analytics: true
        }
      }, {
        http_method: "OPTIONS"
        regex: "^/api-umbrella/v1/users"
        settings: {
          disable_api_key: true
        }
      }]
    },
  ]
  internal_apis: [...#api_backend] | *_default_internal_apis

  apis: [...#api_backend] | *[]

  #website_backend: {
    id?: string
    frontend_host: string
    backend_host?: string
    backend_protocol?: string
    server_host: string
    server_port: uint16 | "{{static_site.port}}"
  }
  _default_internal_website_backends: [...#website_backend] & [
    {
      id: "api-umbrella-website-backend"
      frontend_host: "{{router.web_app_host}}"
      backend_protocol: "http"
      server_host: "{{static_site.host}}"
      server_port: "{{static_site.port}}"
    }
  ]
  internal_website_backends: [...#website_backend] | *_default_internal_website_backends

  website_backends: [...#website_backend] | *[]

  ban: {
    user_agents?: [...string]
    ips?: [...string]
    response: {
      status_code: uint | *403
      delay: uint | *0
      message: string | *"Please contact us for assistance."
    }
  }

  ember_server: {
    port: uint16 | *14050
    live_reload_port: uint16 | *14051
  }

  unbound: {
    port: uint16 | *13100
    control_port: uint16 | *13101
  }

  mailpit: {
    bind_addr: string | *"127.0.0.1"
    smtp_port: uint16 | *13102
    http_port: uint16 | *13103
  }

  glauth: {
    port: uint16 | *13104
  }

  caddy: {
    http_port: uint16 | *13105
    https_port: uint16 | *13106
  }

  umask: string | *"0027"

  geoip: {
    db_path: string | *path.Join([db_dir, "geoip/GeoLite2-City.mmdb"])
    db_update_frequency: uint | false | *86400 // 24 hours
    db_update_age: uint | *79200 // 22 hours
    maxmind_license_key?: string | null
    city_download_url: string | *"https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&suffix=tar.gz"
    s3_cache: {
      enabled: bool | *false
      aws_access_key_id?: string
      aws_secret_access_key?: string
      region?: string
      bucket?: string
    }
  }

  override_public_http_port?: uint16
  override_public_https_port?: uint16
  override_public_http_proto?: "http" | "https"
  override_public_https_proto?: "http" | "https"

  contact_url: string | *"/contact/"
  admin_contact_url: string | *"/contact/"

  http_proxy?: string
  https_proxy?: string
  no_proxy?: string

  version?: uint16

  "_test_config": {
    default_null_override_hash: _ | *null
    default_null_override_string: _ | *null
    default_empty_hash_override_hash: _ | *{}
  }
}

#schema & {}

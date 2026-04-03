local deepcopy = require("pl.tablex").deepcopy
local file_config = require("api-umbrella.utils.load_config")()
local getfiles = require("pl.dir").getfiles
local http = require "resty.http"
local json_decode = require("cjson").decode
local json_encode = require "api-umbrella.utils.json_encode"
local path_join = require "api-umbrella.utils.path_join"
local writefile = require("pl.utils").writefile

local re_find = ngx.re.find
local sleep = ngx.sleep

local control_plane_data_dir = path_join(file_config["run_dir"], "envoy-control-plane/data")
local control_plane_data_tmp_dir = path_join(file_config["run_dir"], "envoy-control-plane/tmp")
local control_plane_data_watched_dir = path_join(file_config["run_dir"], "envoy-control-plane/watched")
local control_plane_expected_paths = {}

local dns_resolver_config = {
  name = "envoy.network.dns_resolver.cares",
  typed_config = {
    ["@type"] = "type.googleapis.com/envoy.extensions.network.dns_resolver.cares.v3.CaresDnsResolverConfig",
    resolvers = file_config["dns_resolver"]["_nameservers_envoy"],
    dns_resolver_options = {
      no_default_search_domain = true,
    },
  },
}

local dns_lookup_family = "V4_PREFERRED"
if not file_config["dns_resolver"]["allow_ipv6"] then
  dns_lookup_family = "V4_ONLY"
end

local dns_cache_config = {
  name = "dynamic_forward_proxy_cache_config",
  typed_dns_resolver_config = dns_resolver_config,
  dns_lookup_family = dns_lookup_family,
}

local base_access_log = {
  name = "envoy.access_loggers.file",
  typed_config = {
    log_format = {
      json_format = {
        time = "%START_TIME%",
        ip = "%REQ(X-FORWARDED-FOR)%",
        method = "%REQ(:METHOD)%",
        scheme = "%REQ(:SCHEME)%",
        uri = "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%",
        proto = "%PROTOCOL%",
        status = "%RESPONSE_CODE%",
        user_agent = "%REQ(USER-AGENT)%",
        id = "%REQ(X-API-UMBRELLA-REQUEST-ID?X-REQUEST-ID)%",
        cache = "%REQ(X-CACHE)%",
        host = "%REQ(:AUTHORITY)%",
        resp_size = "%BYTES_SENT%",
        req_size = "%BYTES_RECEIVED%",
        duration = "%DURATION%",
        req_dur = "%REQUEST_DURATION%",
        req_tx_dur = "%REQUEST_TX_DURATION%",
        resp_dur = "%RESPONSE_DURATION%",
        resp_tx_dur = "%RESPONSE_TX_DURATION%",
        resp_flags = "%RESPONSE_FLAGS%",
        resp_detail = "%RESPONSE_CODE_DETAILS%",
        con_details = "%CONNECTION_TERMINATION_DETAILS%",
        up_attempts = "%UPSTREAM_REQUEST_ATTEMPT_COUNT%",
        up_addr = "%UPSTREAM_REMOTE_ADDRESS%",
        up_proto = "%UPSTREAM_PROTOCOL%",
        up_tls_ver = "%UPSTREAM_TLS_VERSION%",
        up_fail = "%UPSTREAM_TRANSPORT_FAILURE_REASON%",
        up_dur = "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%",
      },
      omit_empty_values = true,
    },
  },
}

if file_config["log"]["destination"] == "console" then
  base_access_log["typed_config"]["@type"] = "type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog"
else
  base_access_log["typed_config"]["@type"] = "type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog"
end

local function build_cluster_resource(cluster_name, options)
  local resource = {
    ["@type"] = "type.googleapis.com/envoy.config.cluster.v3.Cluster",
    name = cluster_name,
    cluster_type = {
      name = "envoy.clusters.strict_dns",
      typed_config = {
        ["@type"] = "type.googleapis.com/envoy.extensions.clusters.dns.v3.DnsCluster",
        typed_dns_resolver_config = dns_resolver_config,
        respect_dns_ttl = true,
        dns_lookup_family = dns_lookup_family,
      },
    },
    wait_for_warm_on_init = false,
    ignore_health_on_host_removal = true,
    load_assignment = {
      cluster_name = cluster_name,
      endpoints = {
        {
          lb_endpoints = {},
        },
      },
    },
    typed_extension_protocol_options = {
      ["envoy.extensions.upstreams.http.v3.HttpProtocolOptions"] = {
        ["@type"] = "type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions",
        -- Make all API backend requests over HTTP 1.1 (instead of HTTP 2 or
        -- 3). Since our nginx layer already downgraded any proxied requests to
        -- HTTP 1.1 (since nginx doesn't currently support proxying via other
        -- versions), it seems simplest to stick with that approach (even
        -- though Envoy could proxy using a different version).
        explicit_http_config = {
          http_protocol_options = {},
        },
        common_http_protocol_options = {
          -- Idle timeout for keepalive connections to upstream servers (API
          -- backends).
          --
          -- Since API backends can be remote, keepalive connections can be
          -- important to improving performance by keeping pre-established
          -- connections around.
          idle_timeout = file_config["router"]["api_backends"]["keepalive_idle_timeout"] .. "s",

          -- Maximum lifetime for any connection to an API backend, regardless
          -- of activity. This ensures connections are periodically
          -- re-established so that DNS or routing changes on the backend side
          -- are picked up in a timely fashion, rather than holding open
          -- connections indefinitely.
          max_connection_duration = file_config["router"]["api_backends"]["keepalive_connections_max_age"] .. "s",
        },
      },
    },
    connect_timeout = file_config["envoy"]["_connect_timeout"],
    upstream_connection_options = {
      tcp_keepalive = {
        keepalive_probes = 2,
        keepalive_time = 15,
        keepalive_interval = 5,
      },
    },
  }

  -- Use the `negative_ttl` time as Envoy's DNS refresh rate.
  --
  -- Since we have `respect_dns_ttl` enabled, successful DNS requests will use
  -- that refresh rate instead of this one. That means this setting is really
  -- only used in failure situations. We configure `dns_refresh_rate` to
  -- provide the TTL for successful, but negative responses (like NXDOMAIN
  -- responses), while `dns_failure_refresh_rate` is used if the DNS servers
  -- themselves are down/unresponsive.
  if file_config["dns_resolver"]["negative_ttl"] then
    resource["cluster_type"]["typed_config"]["dns_refresh_rate"] = file_config["dns_resolver"]["negative_ttl"] .. "s"
    resource["cluster_type"]["typed_config"]["dns_failure_refresh_rate"] = {
      base_interval = file_config["dns_resolver"]["negative_ttl"] .. "s",
      max_interval = file_config["dns_resolver"]["negative_ttl"] .. "s",
    }
  end

  local servers
  local tls_sni

  if options["api_backend"] then
    if options["api_backend"]["balance_algorithm"] == "least_conn" then
      resource["lb_policy"] = "LEAST_REQUEST"
    elseif options["api_backend"]["balance_algorithm"] == "round_robin" then
      resource["lb_policy"] = "ROUND_ROBIN"
    elseif options["api_backend"]["balance_algorithm"] == "ip_hash" then
      resource["lb_policy"] = "RING_HASH"
    end

    servers = options["api_backend"]["servers"]

    if options["api_backend"]["backend_protocol"] == "https" then
      tls_sni =  options["api_backend"]["backend_host"]
    end
  end

  if options["website_backend"] then
    resource["lb_policy"] = "LEAST_REQUEST"

    servers = {
      {
        host = options["website_backend"]["server_host"],
        port = options["website_backend"]["server_port"]
      },
    }

    if options["website_backend"]["backend_protocol"] == "https" then
      tls_sni = options["website_backend"]["_backend_host"]
    end
  end

  if servers then
    local any_servers_ipv6 = false
    local any_servers_hostname = false

    for _, server in ipairs(servers) do
      local host = server["host"]
      if string.find(host, ":", nil, true) then
        any_servers_ipv6 = true
        server["_host_type"] = "ipv6"
      else
        local find_from, _, find_err = re_find(host, [[^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$]], "jo")
        if find_err then
          ngx.log(ngx.ERR, "regex error: ", find_err)
        end

        if find_from then
          server["_host_type"] = "ipv4"
        else
          any_servers_hostname = true
          server["_host_type"] = "hostname"
        end
      end
    end

    -- Envoy does not currently support a mixture of IPv6 and hostnames:
    --
    -- https://github.com/envoyproxy/envoy/issues/18606
    -- https://github.com/envoyproxy/envoy/pull/18945
    --
    -- If only IP addresses are detected, then use Envoy's "STATIC" mode to
    -- properly connect to IPv6 addresses. But if there is a mixture of IPv6
    -- and hostnames, ignore the IPv6 addresses, and just use the hostnames as
    -- a temporary workaround (but hopefully we can revisit this once this is
    -- fixed in Envoy).
    if any_servers_ipv6 then
      if not any_servers_hostname then
        resource["type"] = "STATIC"
      end
    end

    for _, server in ipairs(servers) do
      if any_servers_ipv6 and any_servers_hostname and server["_host_type"] == "ipv6" then
        ngx.log(ngx.WARN, "API backend '" .. resource["name"] .. "' has a mixture of IPv6 and non-IPv6 servers. This configuration is not yet supported. Ignoring IPv6 servers.")
      else
        table.insert(resource["load_assignment"]["endpoints"][1]["lb_endpoints"], {
          endpoint = {
            address = {
              socket_address = {
                address = server["host"],
                port_value = server["port"],
              },
            },
          },
        })
      end
    end
  end

  if tls_sni then
    resource["transport_socket"] = {
      name = "envoy.transport_sockets.tls",
      typed_config = {
        ["@type"] = "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext",
        sni = tls_sni,
        common_tls_context = {
          tls_params = {
            cipher_suites = file_config["envoy"]["tls_cipher_suites"],
            ecdh_curves = file_config["envoy"]["tls_ecdh_curves"],
          },
        },
      },
    }
  end

  return resource
end

local function build_virtual_host_resource(options)
  local virtual_host = {
    name = options["domain"],
    domains = { options["domain"] },
    routes = {
      {
        match = {
          prefix = "/",
        },
        route = {
          cluster = options["cluster"],
          host_rewrite_header = "x-api-umbrella-backend-host",
          timeout = file_config["envoy"]["_route_timeout"],
        },
      },
    },
    retry_policy = {
      -- Retry connections if the connection was never established (eg, if the
      -- API backend was temporarily down or a keepalive connection was
      -- killed).
      retry_on = "connect-failure,reset,http3-post-connect-failure",
      num_retries = 2,
    },
  }

  return virtual_host
end

local function build_listener()
  local access_log = deepcopy(base_access_log)
  access_log["typed_config"]["log_format"]["json_format"]["listener"] = "router"
  if file_config["log"]["destination"] ~= "console" then
    access_log["typed_config"]["path"] = path_join(file_config["log_dir"], "envoy/access.log")
  end

  local listener = {
    ["@type"] = "type.googleapis.com/envoy.config.listener.v3.Listener",
    name = "router",
    address = {
      socket_address = {
        address = file_config["envoy"]["listen"]["host"],
        port_value = file_config["envoy"]["listen"]["port"],
      },
    },
    filter_chains = {
      {
        filters = {
          {
            name = "envoy.http_connection_manager",
            typed_config = {
              ["@type"] = "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager",
              stat_prefix = "router",
              common_http_protocol_options = {
                max_headers_count = 200,
                -- Idle timeout for keepalive connections to downstream server
                -- (Traffic Server).
                --
                -- We will buffer Traffic Server's own idle timeout, since
                -- Traffic Server should really be responsible for closing its
                -- own connections, so this shouldn't necessarily kick in.
                -- However, we will still add a timeout here since we've seen
                -- cases where Traffic Server doesn't close idle connections as
                -- expected (like if Traffic Server's
                -- `http.per_server.connection.min` setting is set).
                idle_timeout = file_config["trafficserver"]["records"]["http"]["keep_alive_no_activity_timeout_out"] + 5 .. "s"
              },
              generate_request_id = false,
              server_header_transformation = "PASS_THROUGH",
              http_filters = {
                {
                  name = "envoy.filters.http.router",
                  typed_config = {
                    ["@type"] = "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router",
                    suppress_envoy_headers = true,
                  },
                },
              },
              rds = {
                route_config_name = "api-umbrella-route-configuration",
                config_source = {
                  resource_api_version = "V3",
                  ads = {},
                },
              },
              stream_idle_timeout = file_config["envoy"]["_stream_idle_timeout"],
              access_log = {
                access_log,
              },

              -- Enable this option, since Envoy is sitting behind other
              -- proxies.
              -- https://www.envoyproxy.io/docs/envoy/latest/configuration/best_practices/level_two#best-practices-level2
              -- https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/network/http_connection_manager/v3/http_connection_manager.proto#envoy-v3-api-field-extensions-filters-network-http-connection-manager-v3-httpconnectionmanager-stream-error-on-invalid-http-message
              stream_error_on_invalid_http_message = true,
            },
          },
        },
      },
    },
  }

  if file_config["envoy"]["scheme"] == "https" then
    listener["filter_chains"][1]["transport_socket"] = {
      name = "envoy.transport_sockets.tls",
      typed_config = {
        ["@type"] = "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext",
        common_tls_context = {
          tls_certificates = {
            {
              certificate_chain = {
                inline_string = file_config["envoy"]["tls_certificate"]["certificate_chain"],
              },
              private_key = {
                inline_string = file_config["envoy"]["tls_certificate"]["private_key"],
              },
            },
          },
        },
      },
    }
  end

  return listener
end

local function build_route_configuration()
  local route_configuration = {
    ["@type"] = "type.googleapis.com/envoy.config.route.v3.RouteConfiguration",
    name = "api-umbrella-route-configuration",
    virtual_hosts = {},
    -- Note: This backend host header isn't necessary for backends to receive
    -- and ideally we'd strip it. However, removing it breaks our ability to
    -- use it in the "host_rewrite_header" option. So we will pass it along to
    -- API backends unless Envoy allows for better ordering of this in the
    -- future.
    -- request_headers_to_remove = {
    --   "x-api-umbrella-backend-host",
    -- },
    response_headers_to_add = {
      {
        append_action = "OVERWRITE_IF_EXISTS_OR_ADD",
        header = {
          key = "x-api-umbrella-backend-resolved-host",
          value = "%UPSTREAM_REMOTE_ADDRESS%",
        },
      },
      {
        append_action = "OVERWRITE_IF_EXISTS_OR_ADD",
        header = {
          key = "x-api-umbrella-backend-response-code-details",
          value = "%RESPONSE_CODE_DETAILS%",
        },
      },
      {
        append_action = "OVERWRITE_IF_EXISTS_OR_ADD",
        header = {
          key = "x-api-umbrella-backend-response-flags",
          value = "%RESPONSE_FLAGS%",
        },
      },
    },
  }

  return route_configuration
end

local function populate_backend_resources(active_config, clusters, route_configuration)
  for _, api_backend in ipairs(active_config["api_backends"]) do
    local cluster_resource = build_cluster_resource("api-backend-cluster-" .. api_backend["id"], {
      api_backend = api_backend,
    })
    table.insert(clusters, cluster_resource)

    local virtual_host_resource = build_virtual_host_resource({
      domain = "api-backend-" .. api_backend["id"],
      cluster = cluster_resource["name"],
    })
    table.insert(route_configuration["virtual_hosts"], virtual_host_resource)
  end

  for _, website_backend in ipairs(active_config["website_backends"]) do
    local cluster_resource = build_cluster_resource("website-backend-cluster-" .. website_backend["id"], {
      website_backend = website_backend,
    })
    table.insert(clusters, cluster_resource)

    local virtual_host_resource = build_virtual_host_resource({
      domain = "website-backend-" .. website_backend["id"],
      cluster = cluster_resource["name"],
    })
    table.insert(route_configuration["virtual_hosts"], virtual_host_resource)
  end
end

local function build_http_proxy_cluster()
  local cluster = {
    ["@type"] = "type.googleapis.com/envoy.config.cluster.v3.Cluster",
    name = "http-proxy",
    lb_policy = "CLUSTER_PROVIDED",
    cluster_type = {
      name = "envoy.clusters.dynamic_forward_proxy",
      typed_config = {
        ["@type"] = "type.googleapis.com/envoy.extensions.clusters.dynamic_forward_proxy.v3.ClusterConfig",
        dns_cache_config = dns_cache_config,
      },
    },
  }

  return cluster
end

local function build_http_proxy_listener()
  local access_log = deepcopy(base_access_log)
  access_log["typed_config"]["log_format"]["json_format"]["listener"] = "http-proxy"
  if file_config["log"]["destination"] ~= "console" then
    access_log["typed_config"]["path"] = path_join(file_config["log_dir"], "envoy/http_proxy_access.log")
  end

  local permissions = {}

  for _, allowed_domain in ipairs(file_config["envoy"]["http_proxy"]["allowed_domains"]) do
    table.insert(permissions, {
      header = {
        name = ":authority",
        string_match = {
          exact = allowed_domain,
        },
      },
    })
  end

  local listener = {
    ["@type"] = "type.googleapis.com/envoy.config.listener.v3.Listener",
    name = "http-proxy",
    address = {
      socket_address = {
        address = file_config["envoy"]["http_proxy"]["listen"]["host"],
        port_value = file_config["envoy"]["http_proxy"]["listen"]["port"],
      },
    },
    filter_chains = {
      {
        filters = {
          {
            name = "envoy.filters.network.http_connection_manager",
            typed_config = {
              ["@type"] = "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager",
              stat_prefix = "http-proxy",
              route_config = {
                name = "local_route",
                virtual_hosts = {
                  {
                    name = "local_service",
                    domains = {"*"},
                    routes = {
                      {
                        match = {
                          connect_matcher = {},
                        },
                        route = {
                          cluster = "http-proxy",
                          upgrade_configs = {
                            {
                              upgrade_type = "CONNECT",
                              connect_config = {},
                            },
                          },
                        },
                      },
                      {
                        match = {
                          prefix = "/",
                        },
                        route = {
                          cluster = "http-proxy",
                        },
                      },
                    },
                  }
                },
              },
              http_filters = {
                {
                  name = "envoy.filters.http.rbac",
                  typed_config = {
                    ["@type"] = "type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC",
                    rules = {
                      action = "ALLOW",
                      policies = {
                        policy = {
                          permissions = permissions,
                          principals = {
                            {
                              any = true,
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  name = "envoy.filters.http.dynamic_forward_proxy",
                  typed_config = {
                    ["@type"] = "type.googleapis.com/envoy.extensions.filters.http.dynamic_forward_proxy.v3.FilterConfig",
                    dns_cache_config = dns_cache_config,
                  },
                },
                {
                  name = "envoy.filters.http.router",
                  typed_config = {
                    ["@type"] = "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router",
                    suppress_envoy_headers = true,
                  },
                },
              },
              http2_protocol_options = {
                allow_connect = true,
              },
              access_log = {
                access_log,
              },
            },
          },
        },
      },
    },
  }

  return listener
end

local function build_smtp_proxy_cluster()
  local cluster_name = "smtp-proxy"
  local cluster = {
    ["@type"] = "type.googleapis.com/envoy.config.cluster.v3.Cluster",
    name = cluster_name,
    type = "LOGICAL_DNS",
    wait_for_warm_on_init = false,
    typed_dns_resolver_config = dns_resolver_config,
    dns_lookup_family = dns_lookup_family,
    load_assignment = {
      cluster_name = cluster_name,
      endpoints = {
        {
          lb_endpoints = {
            {
              endpoint = {
                address = {
                  socket_address = {
                    address = file_config["envoy"]["smtp_proxy"]["endpoint"]["host"],
                    port_value = file_config["envoy"]["smtp_proxy"]["endpoint"]["port"],
                  },
                },
              },
            }
          },
        },
      },
    },
  }

  return cluster
end

local function build_smtp_proxy_listener()
  local access_log = deepcopy(base_access_log)
  access_log["typed_config"]["log_format"]["json_format"]["listener"] = "smtp-proxy"
  if file_config["log"]["destination"] ~= "console" then
    access_log["typed_config"]["path"] = path_join(file_config["log_dir"], "envoy/smtp_proxy_access.log")
  end

  local listener = {
    ["@type"] = "type.googleapis.com/envoy.config.listener.v3.Listener",
    name = "smtp-proxy",
    address = {
      socket_address = {
        address = file_config["envoy"]["smtp_proxy"]["listen"]["host"],
        port_value = file_config["envoy"]["smtp_proxy"]["listen"]["port"],
      },
    },
    filter_chains = {
      {
        filters = {
          {
            name = "envoy.filters.network.tcp_proxy",
            typed_config = {
              ["@type"] = "type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy",
              stat_prefix = "smtp-proxy",
              cluster = "smtp-proxy",
              access_log = {
                access_log,
              },
            },
          },
        },
      },
    },
  }

  return listener
end

local function write_control_plane_config_file(filename, contents, data_dir)
  if data_dir == nil then
    data_dir = control_plane_data_dir
  end

  -- Writ the file and move into place atomically, so there's no possibility of
  -- a partially written file being picked up.
  local tmp_path = path_join(control_plane_data_tmp_dir, filename)
  local path = path_join(data_dir, filename)
  writefile(tmp_path, contents)
  os.rename(tmp_path, path)

  -- Keep track of the known config file paths.
  control_plane_expected_paths[path] = true
end

local function update_control_plane(active_config, clusters, listeners, route_configuration)
  control_plane_expected_paths = {}
  control_plane_expected_paths[path_join(control_plane_data_dir, "snapshot_version")] = true

  for _, resource in ipairs(clusters) do
    write_control_plane_config_file("cluster-" .. resource["name"] .. ".json", json_encode(resource))
  end

  for _, resource in ipairs(listeners) do
    write_control_plane_config_file("listener-" .. resource["name"] .. ".json", json_encode(resource))
  end

  write_control_plane_config_file("route-configuration.json", json_encode(route_configuration))

  -- Remove any files from the data directory that shouldn't be there any
  -- longer (eg, from old cluster files).
  local data_paths = getfiles(control_plane_data_dir)
  if data_paths then
    for _, data_path in ipairs(data_paths) do
      if not control_plane_expected_paths[data_path] then
        os.remove(data_path)
      end
    end
  end

  -- Write the special "snapshot_version" file last which is what will actually
  -- trigger this new config version getting applied.
  write_control_plane_config_file("snapshot_version", active_config["envoy_version"])

  -- Write a copy into the watched directory to trigger a full reload of all
  -- the config files. We don't just watch the main data directory to prevent
  -- lots of duplicative watch events being triggered and piling up when many
  -- config files are being written at once (eg, at startup).
  write_control_plane_config_file("snapshot_version", active_config["envoy_version"], control_plane_data_watched_dir)
end

local function wait_for_live_config(envoy_version, clusters)
  local httpc = http.new()
  local connect_ok, connect_err = httpc:connect({
    scheme = "http",
    host = file_config["envoy"]["admin"]["host"],
    port = file_config["envoy"]["admin"]["port"],
  })

  if not connect_ok then
    httpc:close()
    return nil, "envoy admin connect error: " .. (connect_err or "")
  end

  local ready = false
  local ready_err
  local versions_ready = false
  local clusters_ready = false
  for _ = 1, 50 do
    if not versions_ready then
      local stats_res, stats_err = httpc:request({
        method = "GET",
        path = "/stats?format=json&filter=\\.version_text$",
      })
      if stats_err then
        httpc:close()
        return nil, "envoy admin request error: " .. (stats_err or "")
      end

      local stats_body, stats_body_err = stats_res:read_body()
      if stats_body_err then
        httpc:close()
        return nil, "envoy admin read body error: " .. (stats_body_err or "")
      end

      local stats = json_decode(stats_body)
      for _, stat in ipairs(stats["stats"]) do
        if stat["value"] == "v" .. (envoy_version or "") then
          versions_ready = true
        else
          versions_ready = false
          ready_err = stat["name"] .. " version: " .. stat["value"]
          break
        end
      end
    end

    if not clusters_ready then
      local clusters_res, clusters_err = httpc:request({
        method = "GET",
        path = "/clusters?format=json",
      })
      if clusters_err then
        httpc:close()
        return nil, "envoy admin request error: " .. (clusters_err or "")
      end

      local clusters_body, clusters_body_err = clusters_res:read_body()
      if clusters_body_err then
        httpc:close()
        return nil, "envoy admin read body error: " .. (clusters_body_err or "")
      end

      local live_clusters = json_decode(clusters_body)
      local initialized_cluster_names = {}
      for _, cluster in ipairs(live_clusters["cluster_statuses"]) do
        initialized_cluster_names[cluster["name"]] = true
      end
      for _, cluster in ipairs(clusters) do
        if not initialized_cluster_names[cluster["name"]] then
          clusters_ready = false
          ready_err = "cluster not initialized: " .. cluster["name"]
          break
        else
          clusters_ready = true
        end
      end
    end

    if versions_ready and clusters_ready then
      ready = true
      break
    else
      sleep(0.1)
    end
  end

  local keepalive_ok, keepalive_err = httpc:set_keepalive()
  if not keepalive_ok then
    httpc:close()
    return nil, "envoy admin keepalive error: " .. (keepalive_err or "")
  end

  if not ready then
    return nil, "envoy admin timed out waiting for configuration to be live. Waiting for: " .. (envoy_version or "") .. ", " .. (ready_err or "")
  end
end

return function(active_config)
  local clusters = {}

  local listeners = {
    build_listener(),
  }
  local route_configuration = build_route_configuration()
  populate_backend_resources(active_config, clusters, route_configuration)

  if file_config["envoy"]["http_proxy"]["enabled"] then
    table.insert(clusters, build_http_proxy_cluster())
    table.insert(listeners, build_http_proxy_listener())
  end

  if file_config["envoy"]["smtp_proxy"]["enabled"] then
    table.insert(clusters, build_smtp_proxy_cluster())
    table.insert(listeners, build_smtp_proxy_listener())
  end

  update_control_plane(active_config, clusters, listeners, route_configuration)

  wait_for_live_config(active_config["envoy_version"], clusters)
end

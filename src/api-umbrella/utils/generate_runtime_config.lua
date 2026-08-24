local append_array = require "api-umbrella.utils.append_array"
local array_includes = require "api-umbrella.utils.array_includes"
local cache_computed_api_backend_settings = require("api-umbrella.utils.active_config_store.cache_computed_api_backend_settings")
local deep_defaults = require "api-umbrella.utils.deep_defaults"
local deep_merge_overwrite_arrays = require "api-umbrella.utils.deep_merge_overwrite_arrays"
local deepcopy = require("pl.tablex").deepcopy
local dirname = require("posix.libgen").dirname
local getgrgid = require("posix.grp").getgrgid
local getpwuid = require("posix.pwd").getpwuid
local host_normalize = require "api-umbrella.utils.host_normalize"
local invert_table = require "api-umbrella.utils.invert_table"
local is_empty = require "api-umbrella.utils.is_empty"
local isfile = require("pl.path").isfile
local iso8601_to_timestamp = require("api-umbrella.utils.time").iso8601_to_timestamp
local json_decode = require("cjson").decode
local json_encode = require "api-umbrella.utils.json_encode"
local mkdir_p = require "api-umbrella.utils.mkdir_p"
local nillify_json_nulls = require "api-umbrella.utils.nillify_json_nulls"
local path_exists = require "api-umbrella.utils.path_exists"
local path_join = require "api-umbrella.utils.path_join"
local pl_utils = require "pl.utils"
local random_token = require "api-umbrella.utils.random_token"
local set_hostname_regex = require "api-umbrella.utils.active_config_store.set_hostname_regex"
local shell_blocking_capture = require("shell-games").capture
local stat = require "posix.sys.stat"
local strip = require("pl.stringx").strip
local unistd = require "posix.unistd"
local url_parse = require "api-umbrella.utils.url_parse"

local chmod = stat.chmod
local chown = unistd.chown
local getegid = unistd.getegid
local geteuid = unistd.geteuid
local readfile = pl_utils.readfile
local setpid = unistd.setpid
local umask = stat.umask
local writefile = pl_utils.writefile

-- Fetch the DNS nameservers in use on this server out of the /etc/resolv.conf
-- file.
local function read_resolv_conf_nameservers()
  local nameservers = {}

  local resolv_path = "/etc/resolv.conf"
  local resolv_file, err = io.open(resolv_path, "r")
  if err then
    ngx.log(ngx.WARN, "WARNING: Failed to open file: ", err)
  else
    for line in resolv_file:lines() do
      local nameserver = string.match(line, "^%s*nameserver%s+(.+)$")
      if nameserver then
        nameserver = strip(nameserver)
        if not is_empty(nameserver) then
          table.insert(nameservers, nameserver)
        end
      end
    end

    resolv_file:close()
  end

  return nameservers
end

local function process_api_backends(config)
  local keys = {
    "internal_apis",
    "apis",
  }
  for _, key in ipairs(keys) do
    if config[key] then
      for _, api in ipairs(config[key]) do
        if api["frontend_host"] == "{{router.web_app_host}}" then
          api["frontend_host"] = config["router"]["web_app_host"]
        end

        if api["servers"] then
          for _, server in ipairs(api["servers"]) do
            if server["host"] == "{{web.host}}" then
              server["host"] = config["web"]["host"]
            elseif server["host"] == "{{api_server.host}}" then
              server["host"] = config["api_server"]["host"]
            end

            if server["port"] == "{{web.port}}" then
              server["port"] = config["web"]["port"]
            elseif server["port"] == "{{api_server.port}}" then
              server["port"] = config["api_server"]["port"]
            end
          end
        end
      end
    end
  end

  local combined_apis = {}
  append_array(combined_apis, config["internal_apis"] or {})
  append_array(combined_apis, config["apis"] or {})
  config["_apis"] = combined_apis
  config["apis"] = nil
  config["internal_apis"] = nil
end

local function process_website_backends(config)
  local keys = {
    "internal_website_backends",
    "website_backends",
  }
  for _, key in ipairs(keys) do
    if config[key] then
      for _, website in ipairs(config[key]) do
        if website["frontend_host"] == "{{router.web_app_host}}" then
          website["frontend_host"] = config["router"]["web_app_host"]
        end

        if website["server_host"] == "{{static_site.host}}" then
          website["server_host"] = config["static_site"]["host"]
        end

        if website["server_port"] == "{{static_site.port}}" then
          website["server_port"] = config["static_site"]["port"]
        end
      end
    end
  end

  local combined_website_backends = {}
  append_array(combined_website_backends, config["internal_website_backends"] or {})
  append_array(combined_website_backends, config["website_backends"] or {})
  config["_website_backends"] = combined_website_backends
  config["website_backends"] = nil
  config["internal_website_backends"] = nil
end

local function ssl_trusted_certificate_path(config)
  if config["nginx"]["lua_ssl_trusted_certificate"] then
    return config["nginx"]["lua_ssl_trusted_certificate"]
  end

  -- Look for the certificate file in various places based on
  -- https://go.dev/src/crypto/x509/root_linux.go
  local paths = {
    "/etc/ssl/certs/ca-certificates.crt", --  Debian/Ubuntu/Gentoo etc.
    "/etc/pki/tls/certs/ca-bundle.crt", -- Fedora/RHEL 6
    "/etc/ssl/ca-bundle.pem", -- OpenSUSE
    "/etc/pki/tls/cacert.pem", -- OpenELEC
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", -- CentOS/RHEL 7
    "/etc/ssl/cert.pem", -- Alpine Linux
  }
  for _, path in ipairs(paths) do
    if isfile(path) then
      return path
    end
  end

  return nil
end

-- After all the primary config is read from files and combined, perform
-- additional setup for configuration variables that are computed based on
-- other configuration variables. Since these values are computed, they
-- typically aren't subject to defining or overriding in any of the config
-- files.
--
-- For configuration variables that are computed and the user cannot override
-- in the config files, we denote those with an underscore prefix in the name.
local function set_computed_config(config)
  if config["app_env"] == "test" then
    config["log_dir"] = path_join(config["_src_root_dir"], "test/tmp/artifacts/log")
  end

  process_api_backends(config)
  process_website_backends(config)
  config["_default_api_backend_settings"] = deepcopy(config["default_api_backend_settings"])
  cache_computed_api_backend_settings(config, config["_default_api_backend_settings"])

  local trusted_proxies = config["router"]["trusted_proxies"] or {}
  if not array_includes(trusted_proxies, "127.0.0.1") then
    table.insert(trusted_proxies, "127.0.0.1")
  end

  local default_host_exists = false
  for _, host in ipairs(config["hosts"]) do
    set_hostname_regex(host, "hostname")

    if host["default"] then
      default_host_exists = true
    end

    if host["hostname"] == "*" then
      host["_nginx_server_name"] = "_"
    else
      host["_nginx_server_name"] = host["hostname"]
    end

    if host["scheduled_brownouts"] then
      for _, scheduled_brownout in ipairs(host["scheduled_brownouts"]) do
        for _, schedule in ipairs(scheduled_brownout["schedule"]) do
          schedule["_start_time_timestamp"] = iso8601_to_timestamp(schedule["start_time"])
          schedule["_end_time_timestamp"] = iso8601_to_timestamp(schedule["end_time"])
        end
      end
    end
  end

  -- If a default host hasn't been explicitly defined, then add a default
  -- fallback host that will match any hostname (but doesn't include any
  -- host-specific settings in nginx, like rewrites). A default host is
  -- necessary so nginx handles all hostnames, allowing APIs to be matched for
  -- hosts that are only defined in the API backend configuration.
  if not default_host_exists then
    table.insert(config["hosts"], {
      hostname = "*",
      -- Use a slightly different nginx server name to avoid any conflicts with
      -- explicitly defined wildcard hosts (but aren't the default, which
      -- doesn't seem particularly likely). There's nothing actually special
      -- about "_" in nginx, it's just a hostname that won't match anything
      -- real.
      _nginx_server_name = "__",
      default = true,
    })
  end

  local default_hostname
  if config["hosts"] then
    for _, host in ipairs(config["hosts"]) do
      if host["default"] and host["hostname"] then
        default_hostname = host["hostname"]
        break
      end
    end
  end

  if default_hostname then
    config["_default_hostname"] = default_hostname
    config["_default_hostname_normalized"] = host_normalize(default_hostname)
  end

  -- Set the default host used for web application links (for mailers, contact
  -- URLs, etc).
  --
  -- By default, pick this up from the `hosts` array where `default` has been
  -- set to true (this gets put on `_default_hostname` for easier access). But
  -- still allow the web host to be explicitly set via `web.default_host`.
  if not config["web"]["default_host"] then
    config["web"]["default_host"] = config["_default_hostname"]

    -- Fallback to something that will at least generate valid URLs if there's
    -- no default, or the default is "*" (since in this context, a wildcard
    -- doesn't make sense for generating URLs).
    if not config["web"]["default_host"] or config["web"]["default_host"] == "*" then
      config["web"]["default_host"] = "localhost"
    end
  end

  -- Determine the nameservers for DNS resolution. Prefer explicitly configured
  -- nameservers, but fallback to nameservers defined in resolv.conf, and then
  -- Google's DNS servers if nothing else is defined.
  local nameservers
  local resolv_conf_nameservers
  if config["dns_resolver"] and config["dns_resolver"]["nameservers"] then
    nameservers = config["dns_resolver"]["nameservers"]
  end
  if is_empty(nameservers) or config["app_env"] == "test" then
    resolv_conf_nameservers = read_resolv_conf_nameservers()
    if is_empty(nameservers) then
      nameservers = resolv_conf_nameservers
    end
  end
  if is_empty(nameservers) then
    nameservers = { "8.8.8.8", "8.8.4.4" }
  end

  -- Parse the nameservers, allowing for custom DNS ports to be specified in
  -- the OpenBSD resolv.conf format of "[IP]:port".
  config["dns_resolver"]["_nameservers"] = {}
  config["dns_resolver"]["_nameservers_nginx"] = {}
  config["dns_resolver"]["_nameservers_envoy"] = {}
  for _, nameserver in ipairs(nameservers) do
    local ip, port = string.match(nameserver, "^%[(.+)%]:(%d+)$")
    if ip and port then
      nameserver = { ip, port }
      table.insert(config["dns_resolver"]["_nameservers_nginx"], ip .. ":" .. port)
      table.insert(config["dns_resolver"]["_nameservers_envoy"], {
        socket_address = {
          address = ip,
          port_value = tonumber(port),
        }
      })
    else
      table.insert(config["dns_resolver"]["_nameservers_nginx"], nameserver)
      table.insert(config["dns_resolver"]["_nameservers_envoy"], {
        socket_address = {
          address = nameserver,
          port_value = 53,
        }
      })
    end

    table.insert(config["dns_resolver"]["_nameservers"], nameserver)
  end
  if #config["dns_resolver"]["_nameservers_nginx"] > 0 then
    config["dns_resolver"]["_nameservers_nginx"] = table.concat(config["dns_resolver"]["_nameservers_nginx"], " ")
    config["dns_resolver"]["_nameservers_trafficserver"] = config["dns_resolver"]["_nameservers_nginx"]
  else
    config["dns_resolver"]["_nameservers_nginx"] = nil
  end
  config["dns_resolver"]["nameservers"] = nil

  if config["app_env"] == "test" then
    config["dns_resolver"]["_nameservers_unbound"] = {}
    for _, nameserver in ipairs(resolv_conf_nameservers) do
      table.insert(config["dns_resolver"]["_nameservers_unbound"], nameserver)
    end
  end

  if not config["dns_resolver"]["allow_ipv6"] then
    config["dns_resolver"]["_nameservers_nginx"] = config["dns_resolver"]["_nameservers_nginx"] .. " ipv6=off"
  end

  config["opensearch"]["_servers"] = {}
  if config["opensearch"]["hosts"] then
    for _, opensearch_url in ipairs(config["opensearch"]["hosts"]) do
      local parsed, parse_err = url_parse(opensearch_url)
      if not parsed or parse_err then
        ngx.log(ngx.WARN, "WARNING: Failed to parse: " .. (opensearch_url or "") .. " " .. (parse_err or ""))
      else
        parsed["port"] = tonumber(parsed["port"])
        if not parsed["port"] then
          if parsed["scheme"] == "https" then
            parsed["port"] = 443
          elseif parsed["scheme"] == "http" then
            parsed["port"] = 80
          end
        end

        if parsed["scheme"] == "https" then
          parsed["_https?"] = true
        end

        table.insert(config["opensearch"]["_servers"], parsed)
      end
    end
  end

  if not config["analytics"]["outputs"] then
    config["analytics"]["outputs"] = { config["analytics"]["adapter"] }
  end

  local strip_request_cookies = deepcopy(config["strip_cookies"])
  table.insert(strip_request_cookies, "^_api_umbrella_session$")
  table.insert(strip_request_cookies, "^_api_umbrella_csrf_token$")
  config["_strip_request_cookies_regex_non_web_app_backends"] = table.concat(strip_request_cookies, "|")

  if not is_empty(config["strip_cookies"]) then
    config["_strip_request_cookies_regex_web_app_backend"] = table.concat(config["strip_cookies"], "|")
  end

  if not is_empty(config["strip_response_cookies"]) then
    config["_strip_response_cookies_regex"] = table.concat(config["strip_response_cookies"], "|")
  end

  -- Setup the request/response timeouts for the different pieces of the stack.
  -- Since we traverse multiple proxies, we want to make sure the timeouts of
  -- the different proxies are kept in sync.
  --
  -- We will actually stagger the timeouts slightly at each proxy layer to
  -- prevent race conditions. Since the flow of the requests looks like:
  --
  -- [incoming request] => [nginx proxy] => [trafficserver] => [envoy] => [api backends]
  --
  -- Notes:
  --
  -- * Envoy handles the real connection timeout, since it's what's
  --   establishing connections to the underlying API backend servers.
  --
  --   The other layers should have a short connection timeout, since they are
  --   only making local connections.
  -- * We buffer nginx's read/send timeouts so that Traffic Server should
  --   handle all of the real timeouts.
  --
  --   Note that proxy_send_timeout in nginx doesn't seem to be effective when
  --   "proxy_request_buffering" is also off, but we'll still set it with the
  --   buffered amount anyway (but again, Traffic Server is doing the real
  --   timeouts).
  -- * We similarly buffer Envoy's idle/streaming timeouts so that Traffic
  --   Server should handle all of the real activity timeouts.
  --
  --   Perhaps ideally Envoy would handle these timeouts (since it's closest to
  --   the server), but Envoy does not have a separate concept of request and
  --   response streaming timeouts. Plus, Envoy's response codes on timeouts
  --   aren't currently correct
  --   (https://github.com/envoyproxy/envoy/issues/19725). Since Traffic Server
  --   seems to have better error messages and debugging details, that's why
  --   we'll use Traffic Server to perform these activity timeouts.
  -- * The read timeout (the timeout between bytes being received from a
  --   backend) is reflected by Traffic Server's "activity_out" timeout.
  -- * The send timeout (the timeout between bytes being received from the
  --   client request), is reflected by Traffic Server's "activity_in" timeout.
  config["envoy"]["_connect_timeout"] = config["nginx"]["proxy_connect_timeout"] .. "s"
  config["envoy"]["_stream_idle_timeout"] = math.max(config["nginx"]["proxy_send_timeout"], config["nginx"]["proxy_read_timeout"]) + 2 .. "s"
  -- Disable default 15 second timeout on the entire response being returned,
  -- since we will allow long-running streaming responses.
  config["envoy"]["_route_timeout"] = "0s"
  config["trafficserver"]["_connect_attempts_timeout"] = math.min(5, config["nginx"]["proxy_connect_timeout"])
  config["trafficserver"]["_transaction_no_activity_timeout_out"] = config["nginx"]["proxy_read_timeout"]
  config["trafficserver"]["_transaction_no_activity_timeout_in"] = config["nginx"]["proxy_send_timeout"]
  config["nginx"]["_initial_proxy_connect_timeout"] = math.min(5, config["nginx"]["proxy_connect_timeout"])
  config["nginx"]["_initial_proxy_read_timeout"] = config["nginx"]["proxy_read_timeout"] + 4
  config["nginx"]["_initial_proxy_send_timeout"] = config["nginx"]["proxy_send_timeout"] + 4

  if not config["user"] then
    local euid = geteuid()
    if euid then
      local user = getpwuid(euid)
      if user then
        config["_effective_user_id"] = user.pw_uid
        config["_effective_user_name"] = user.pw_name
      end
    end
  end

  if not config["group"] then
    local egid = getegid()
    if egid then
      local group = getgrgid(egid)
      if group then
        config["_effective_group_id"] = group.gr_gid
        config["_effective_group_name"] = group.gr_name
      end
    end
  end

  config["nginx"]["_lua_ssl_trusted_certificate"] = ssl_trusted_certificate_path(config)

  deep_merge_overwrite_arrays(config, {
    _package_path = package.path,
    _package_cpath = package.cpath,
    ["_test_env?"] = (config["app_env"] == "test"),
    ["_development_env?"] = (config["app_env"] == "development"),
    analytics = {
      ["_output_opensearch?"] = array_includes(config["analytics"]["outputs"], "opensearch"),
    },
    opensearch = {
      _first_server = config["opensearch"]["_servers"][1],
    },
    ["_service_egress_enabled?"] = array_includes(config["services"], "egress"),
    ["_service_router_enabled?"] = array_includes(config["services"], "router"),
    ["_service_web_enabled?"] = array_includes(config["services"], "web"),
    router = {
      trusted_proxies = trusted_proxies,
    },
    web = {
      admin = {
        auth_strategies = {
          ["_enabled"] = invert_table(config["web"]["admin"]["auth_strategies"]["enabled"]),
          ["_only_ldap_enabled?"] = (#config["web"]["admin"]["auth_strategies"]["enabled"] == 1 and config["web"]["admin"]["auth_strategies"]["enabled"][1] == "ldap"),
        },
      },
    },
  })

  if config["app_env"] == "development" then
    config["_dev_env_install_dir"] = path_join(config["_src_root_dir"], "build/work/dev-env")
  end

  if config["app_env"] == "test" then
    config["_test_env_install_dir"] = path_join(config["_src_root_dir"], "build/work/test-env")
  end
end

local function set_process_permissions(config)
  if config["group"] then
    setpid("g", config["group"])
  end
  umask(tonumber(config["umask"], 8))
end

local function write_permissioned_file(path, content, config)
  if not path_exists(path) then
    mkdir_p(dirname(path))
    writefile(path, "")
  end

  chmod(path, tonumber("0640", 8))
  if config["group"] then
    chown(path, nil, config["group"])
  end

  writefile(path, content)
end

-- Handle setup of random secret tokens that should be be unique for API
-- Umbrella installations, but should be persisted across restarts.
--
-- In a multi-server setup, these secret tokens will likely need to be
-- explicitly given in the server's /etc/api-umbrella/api-umbrella.yml file so
-- the secrets match across servers, but this provides defaults for a
-- single-server installation.
local function set_cached_random_tokens(config)
  -- Only generate new new tokens if they haven't been explicitly set in the
  -- config files.
  if not config["secret_key"] or not config["static_site"]["api_key"] then
    -- See if there were any previous values for these random tokens on this
    -- server. If so, use any of those values that might be present instead.
    local cached_path = path_join(config["run_dir"], "cached_random_config_values.json")
    local cached

    -- Migrate/convert legacy yaml file to JSON file.
    local legacy_yaml_cached_path = path_join(config["run_dir"], "cached_random_config_values.yml")
    if path_exists(legacy_yaml_cached_path) and not path_exists(cached_path) then
      local cue_result, cue_err = shell_blocking_capture({
        "cue",
        "export",
        "--out", "json",
        legacy_yaml_cached_path,
      })
      if cue_err then
        ngx.log(ngx.WARN, "Failed to convert legacy cached random config data to new format: ", cue_err)
      else
        cached = json_decode(cue_result["output"])
        write_permissioned_file(cached_path, json_encode(cached), config)
        os.remove(legacy_yaml_cached_path)
      end
    else
      local content = readfile(cached_path, true)
      cached = {}
      if content then
        cached = json_decode(content) or {}
        nillify_json_nulls(cached)
      end
    end

    deep_defaults(config, cached)

    -- If the tokens haven't already been written to the cache, generate them.
    if not config["secret_key"] or not config["static_site"]["api_key"] then
      if not config["secret_key"] then
        deep_defaults(cached, {
          secret_key = random_token(64),
        })
      end

      if not config["static_site"]["api_key"] then
        deep_defaults(cached, {
          static_site = {
            api_key = random_token(40),
          },
        })
      end

      -- Persist the cached tokens.
      write_permissioned_file(cached_path, json_encode(cached), config)

      deep_defaults(config, cached)
    end
  end
end

-- Write out the combined and merged config to the runtime file.
--
-- This runtime config reflects the full state of the available config and can
-- be used by other API Umbrella processes for reading the config (without
-- having to actually merge and combine again).
local function write_runtime_config(config)
  write_permissioned_file(config["_runtime_config_path"], json_encode(config), config)
end

local function parse_config()
  local src_root_dir = os.getenv("API_UMBRELLA_SRC_ROOT")
  local cue_args = {
    "cue",
    "export",
    "--out", "json",
    "--all-errors",
    "--inject", "src_root_dir=" .. src_root_dir,
    "--inject", "embedded_root_dir=" .. os.getenv("API_UMBRELLA_EMBEDDED_ROOT"),
  }

  local root_dir = os.getenv("API_UMBRELLA_ROOT")
  if root_dir then
    table.insert(cue_args, "--inject")
    table.insert(cue_args, "root_dir=" .. root_dir)
  end

  local runtime_config_path = os.getenv("API_UMBRELLA_RUNTIME_CONFIG")
  if runtime_config_path then
    table.insert(cue_args, "--inject")
    table.insert(cue_args, "runtime_config_path=" .. runtime_config_path)
  end

  table.insert(cue_args, path_join(src_root_dir, "config/schema.cue"))

  local config_path = os.getenv("API_UMBRELLA_CONFIG") or "/etc/api-umbrella/api-umbrella.yml"
  if path_exists(config_path) then
    table.insert(cue_args, config_path)
  else
    ngx.log(ngx.WARN, "WARNING: Config file does not exist: ", config_path)
  end

  local result, cue_err = shell_blocking_capture(cue_args)
  if cue_err then
    ngx.log(ngx.ERR, "Failed to parse configuration: ", cue_err)
    os.exit(1)
  end

  local config = json_decode(result["output"])
  nillify_json_nulls(config)

  return config
end

return function(options)
  local config = parse_config()
  set_computed_config(config)
  set_process_permissions(config)
  set_cached_random_tokens(config)

  if options and options["persist_runtime_config"] then
    write_runtime_config(config)
  end

  return config
end

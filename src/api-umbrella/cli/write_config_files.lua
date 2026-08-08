local basename = require("posix.libgen").basename
local config = require("api-umbrella.utils.load_config")()
local escape_regex = require "api-umbrella.utils.escape_regex"
local etlua_render = require("etlua").render
local find_cmd = require "api-umbrella.utils.find_cmd"
local invert_table = require "api-umbrella.utils.invert_table"
local json_encode = require "api-umbrella.utils.json_encode"
local mkdir_p = require "api-umbrella.utils.mkdir_p"
local path_exists = require "api-umbrella.utils.path_exists"
local path_join = require "api-umbrella.utils.path_join"
local pl_utils = require "pl.utils"
local shell_blocking_capture_combined = require("shell-games").capture_combined
local stat = require "posix.sys.stat"
local tablex = require "pl.tablex"
local unistd = require "posix.unistd"
local xpcall_error_handler = require "api-umbrella.utils.xpcall_error_handler"

local chmod = stat.chmod
local chown = unistd.chown
local readfile = pl_utils.readfile
local writefile = pl_utils.writefile

local _M = {}

function _M.prepare()
  local dirs = {
    config["db_dir"],
    config["log_dir"],
    config["run_dir"],
    config["tmp_dir"],
    path_join(config["run_dir"], "envoy"),
  }

  for _, directory in ipairs(dirs) do
    mkdir_p(directory)
  end
end

local function generate_cert(subject, key_filename, crt_filename)
  local ssl_dir = path_join(config["etc_dir"], "ssl");
  local ssl_key_path = path_join(ssl_dir, key_filename);
  local ssl_crt_path = path_join(ssl_dir, crt_filename);

  if not path_exists(ssl_key_path) or not path_exists(ssl_crt_path) then
    mkdir_p(ssl_dir)
    local _, err = shell_blocking_capture_combined({ "openssl", "req", "-new", "-newkey", "rsa:2048", "-days", "3650", "-nodes", "-x509", "-subj", subject, "-keyout", ssl_key_path, "-out", ssl_crt_path })
    if err then
      print(err)
      os.exit(1)
    end
  end
end

local function generate_self_signed_cert()
  local cert_required = false
  if config["hosts"] then
    for _, host in ipairs(config["hosts"]) do
      if not host["ssl_cert"] then
        cert_required = true
        break
      end
    end
  end

  if cert_required then
    generate_cert("/O=API Umbrella/CN=apiumbrella.example.com", "self_signed.key", "self_signed.crt")
  end
end

local function set_template_permissions(file_path, install_filename)
  if config["group"] then
    chown(file_path, nil, config["group"])
  end

  if install_filename == "rc.log" or install_filename == "rc.main" or install_filename == "rc.perp" then
    chmod(file_path, tonumber("0750", 8))
  else
    chmod(file_path, tonumber("0640", 8))
  end
end

local function write_templates()
  local created_dirs = {}
  local template_root = path_join(config["_src_root_dir"], "templates/etc")

  local file_paths, file_paths_err = find_cmd(template_root, { "-type", "f" })
  if file_paths_err then
    print(file_paths_err)
    os.exit(1)
  end

  for _, template_path in ipairs(file_paths) do
    local template_filename = basename(template_path)

    local process = true
    local is_hidden = (string.sub(template_filename, 1, 1) == ".")
    if is_hidden then
      process = false
    end

    local is_dev_file = (string.find(template_path, "dev-env", 1, true) ~= nil)
    if is_dev_file and config["app_env"] ~= "development" then
      process = false
    end

    local is_test_file = (string.find(template_path, "test-env", 1, true) ~= nil)
    if is_test_file and config["app_env"] ~= "test" then
      process = false
    end

    if process then
      local path_parts, path_match_err = ngx.re.match(template_path, [[^]] .. escape_regex(template_root .. "/") .. [[((.+?/)?([^/]+?))(?:\.(etlua))?$]], "jo")
      if not path_parts then
        print("path not matched: " .. template_path)
        os.exit(1)
      elseif path_match_err then
        print("regex error: " .. path_match_err)
        os.exit(1)
      else
        local install_dir = path_join(config["etc_dir"], path_parts[2] or "")
        local install_path = path_join(config["etc_dir"], path_parts[1])
        local filename = path_parts[3]
        local template_ext = path_parts[4]

        local content = readfile(template_path, true)

        if template_ext == "etlua" then
          local render_ok, render_err
          render_ok, content, render_err = xpcall(etlua_render, xpcall_error_handler, content, { config = config, json_encode = json_encode, path_join = path_join })
          if not render_ok or render_err then
            print("template compile error in " .. template_path ..": " .. (render_err or content))
            os.exit(1)
          end
        end

        -- Only write the file if it differs from the existing file. This helps
        -- prevents some processes, like Trafficserver, from thinking there are
        -- config file updates to process on reloads if the file timestamps
        -- change (even if there aren't actually any changes).
        local _, existing_content = xpcall(readfile, xpcall_error_handler, install_path, true)
        if content ~= existing_content then
          -- Write the config file in an atomic fashion (by writing to a temp
          -- file and then moving into place), so that during reloads the
          -- processes never read a half-written file.
          if not created_dirs[install_dir] then
            mkdir_p(install_dir)
            created_dirs[install_dir] = true
          end

          local temp_filename = "." .. filename .. ".tmp"
          local temp_path = path_join(install_dir, temp_filename)
          local _, write_err = writefile(temp_path, content)
          if write_err then
            print("write failed: ", write_err)
            os.exit(1)
          end
          set_template_permissions(temp_path, filename)

          local rename_ok, rename_err = os.rename(temp_path, install_path)
          if not rename_ok then
            print("Move file failed: " .. rename_err)
            os.exit(1)
          end
        else
          set_template_permissions(install_path, filename)
        end
      end
    end
  end
end

local function write_static_site_key()
  local file_paths = {
    path_join(config["static_site"]["build_dir"], "contact/index.html"),
    path_join(config["static_site"]["build_dir"], "signup/index.html"),
  }
  for _, file_path in ipairs(file_paths) do
    if not path_exists(file_path) then
      print("File does not exist: " .. file_path)
      os.exit(1)
    end

    local content = readfile(file_path)
    local new_content, replacements = string.gsub(content, "apiKey: '.-'", "apiKey: '" .. config["static_site"]["api_key"] .. "'")
    if replacements > 0 then
      local _, write_err = writefile(file_path, new_content)
      if write_err then
        print("write failed: ", write_err)
        os.exit(1)
      end
    end
  end
end

local function set_permissions()
  chmod(config["tmp_dir"], tonumber("1777", 8))

  if config["user"] and config["group"] then
    local user = config["user"]
    local group = config["group"]
    chown(config["db_dir"], nil, group)
    chown(config["log_dir"], nil, group)
    chown(config["run_dir"], user, group)
    chown(config["tmp_dir"], user, group)
    chown(config["var_dir"], nil, group)
    chown(config["etc_dir"], nil, group)
    chown(path_join(config["db_dir"], "geoip"), nil, group)
    chown(path_join(config["etc_dir"], "nginx"), nil, group)
    chown(path_join(config["etc_dir"], "opensearch"), nil, group)
    chown(path_join(config["etc_dir"], "perp"), nil, group)
    chown(path_join(config["etc_dir"], "trafficserver"), nil, group)

    if config["app_env"] == "test" then
      chown(path_join(config["etc_dir"], "test-env"), nil, group)
      chown(path_join(config["etc_dir"], "test-env/mongo-orchestration"), nil, group)
      chown(path_join(config["etc_dir"], "test-env/nginx"), nil, group)
      chown(path_join(config["etc_dir"], "test-env/unbound"), nil, group)
    end
  end

  local service_dirs, service_dirs_err = find_cmd(path_join(config["etc_dir"], "perp"), { "-type", "d" })
  if service_dirs_err then
    print(service_dirs_err)
    os.exit(1)
  end
  for _, service_dir in ipairs(service_dirs) do
    chmod(service_dir, tonumber("0750", 8))
    if config["group"] then
      chown(service_dir, nil, config["group"])
    end
  end
end

local function activate_services()
  local available_services, available_services_dir = find_cmd(path_join(config["_src_root_dir"], "templates/etc/perp"), { "-type", "d" })
  if available_services_dir then
    print(available_services_dir)
    os.exit(1)
  end
  tablex.transform(basename, available_services)
  available_services = invert_table(available_services)

  local active_services = {}
  if config["_service_router_enabled?"] then
    if config["geoip"]["_auto_updater_enabled"] then
      active_services["geoip-auto-updater"] = 1
    end
    active_services["envoy-control-plane"] = 1
    active_services["fluent-bit"] = 1
    active_services["nginx"] = 1
    active_services["trafficserver"] = 1
  end
  if config["_service_egress_enabled?"] then
    active_services["envoy"] = 1
  end
  if config["_service_web_enabled?"] then
    active_services["nginx-web-app"] = 1
  end
  if config["app_env"] == "development" then
    active_services["dev-env-ember-server"] = 1
    active_services["dev-env-example-website-hugo"] = 1
  end
  if config["app_env"] == "test" then
    active_services["test-env-caddy"] = 1
    active_services["test-env-glauth"] = 1
    active_services["test-env-mailpit"] = 1
    active_services["test-env-nginx"] = 1
    active_services["test-env-unbound"] = 1
  end

  -- Loop over the perp controlled services and set the sticky permission bit
  -- for any services that are supposed to be active (this sticky bit is how
  -- perp determines which services to run).
  local installed_service_dirs, installed_service_dirs_err = find_cmd(path_join(config["etc_dir"], "perp"), { "-type", "d" })
  if installed_service_dirs_err then
    print(installed_service_dirs_err)
    os.exit(1)
  end
  for _, service_dir in ipairs(installed_service_dirs) do
    local service_name = basename(service_dir)

    -- Disable any old services that might be installed, but are no longer
    -- present in templates/etc/perp.
    local is_active = false
    if available_services[service_name] and active_services[service_name] then
      is_active = true
    end

    -- Perp's hidden directories don't need the sticky bit.
    local is_hidden = (string.find(service_name, ".", 1, true) == 1)
    if is_hidden then
      is_active = false
    end

    -- Create the log directory for svlogd output for this service.
    if is_active or service_name == ".boot" then
      local service_log_name = service_name
      if service_name == ".boot" then
        service_log_name = "perpd"
      end

      local service_log_dir = path_join(config["log_dir"], service_log_name)
      mkdir_p(service_log_dir)
      local _, log_chmod_err = shell_blocking_capture_combined({ "chmod", "0755", service_log_dir })
      if log_chmod_err then
        print("chmod failed: ", log_chmod_err)
        os.exit(1)
      end
      if config["user"] and config["group"] then
        local _, log_chown_err = shell_blocking_capture_combined({ "chown", config["user"] .. ":" .. config["group"], service_log_dir })
        if log_chown_err then
          print("chown failed: ", log_chown_err)
          os.exit(1)
        end
      end
    end

    -- Set the sticky bit for any active services.
    if is_active then
      chmod(service_dir, tonumber("1750", 8))

      local log_dir = path_join(config["log_dir"], service_name)
      mkdir_p(log_dir)
      chmod(log_dir, tonumber("0750", 8))
      if config["user"] and config["group"] then
        chown(log_dir, config["user"], config["group"])
      end
    else
      chmod(service_dir, tonumber("0750", 8))
    end
  end
end

function _M.all_steps()
  _M.prepare()
  generate_self_signed_cert()
  write_templates()
  write_static_site_key()
  set_permissions()
  activate_services()
end

return _M

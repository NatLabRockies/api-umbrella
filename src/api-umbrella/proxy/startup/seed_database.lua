local config = require("api-umbrella.utils.load_config")()
local deep_merge_overwrite_arrays = require "api-umbrella.utils.deep_merge_overwrite_arrays"

local api_key_prefixer = require("api-umbrella.utils.api_key_prefixer").prefix
local db = require "lapis.db"
local encryptor = require "api-umbrella.utils.encryptor"
local hmac = require "api-umbrella.utils.hmac"
local interval_lock = require "api-umbrella.utils.interval_lock"
local pg_encode_json = require("pgmoon.json").encode_json
local pg_utils = require "api-umbrella.utils.pg_utils"
local random_token = require "api-umbrella.utils.random_token"
local uuid = require "resty.uuid"

local db_raw = db.raw
local sleep = ngx.sleep
local timer_at = ngx.timer.at

local function wait_for_postgres()
  local postgres_alive = false
  local wait_time = 0
  local sleep_time = 0.5
  local max_time = 14
  repeat
    local ok, err = pg_utils.connect()
    if not ok then
      ngx.log(ngx.NOTICE, "failed to establish connection to postgres (this is expected if postgres is starting up at the same time): ", err)
    else
      postgres_alive = true
    end

    if not postgres_alive then
      sleep(sleep_time)
      wait_time = wait_time + sleep_time
    end
  until postgres_alive or wait_time > max_time

  if postgres_alive then
    return true, nil
  else
    return false, "postgres was not ready within " .. max_time  .."s"
  end
end

local function set_stamping()
  pg_utils.query("SET LOCAL audit.application_user_id = '00000000-0000-0000-0000-000000000000'")
  pg_utils.query("SET LOCAL audit.application_user_name = 'api-umbrella-proxy'")
end

local function seed_api_keys()
  local keys = {
    -- static.site.ajax@internal.apiumbrella
    {
      api_key = config["static_site"]["api_key"],
      email = "static.site.ajax@internal.apiumbrella",
      first_name = "API Umbrella Static Site",
      last_name = "Key",
      use_description = "An API key for the API Umbrella static website to use for ajax requests.",
      registration_source = "seed",
      roles = { "api-umbrella-key-creator", "api-umbrella-contact-form" },
      settings = {
        rate_limit_mode = "custom",
        rate_limits = {
          {
            duration = 1 * 60 * 1000, -- 1 minute
            limit_by = "ip",
            limit_to = 5,
            response_headers = false,
          },
          {
            duration = 60 * 60 * 1000, -- 1 hour
            limit_by = "ip",
            limit_to = 20,
            response_headers = true,
          },
        },
      },
    },

    -- web.admin.ajax@internal.apiumbrella
    {
      email = "web.admin.ajax@internal.apiumbrella",
      first_name = "API Umbrella Admin",
      last_name = "Key",
      use_description = "An API key for the API Umbrella admin to use for internal ajax requests.",
      registration_source = "seed",
      roles = { "api-umbrella-key-creator" },
      settings = {
        rate_limit_mode = "unlimited",
      },
    },
  }

  -- Development-only demo API user with a known API key
  if config["app_env"] == "development" then
    table.insert(keys, {
      api_key = "DEMO_KEY_FOR_DEVELOPMENT_ONLY_1234567890",
      email = "demo.developer@example.com",
      first_name = "Demo",
      last_name = "Developer",
      use_description = "Demo API user for local development testing",
      registration_source = "seed",
      terms_and_conditions = true,
    })
  end

  for _, data in ipairs(keys) do
    pg_utils.query("START TRANSACTION")
    set_stamping()

    local result, user_err = pg_utils.query("SELECT * FROM api_users WHERE email = :email ORDER BY created_at LIMIT 1", { email = data["email"] })
    if not result then
      ngx.log(ngx.ERR, "failed to query api_users: ", user_err)
      break
    end

    local user = result[1]
    local user_update = false
    if user then
      deep_merge_overwrite_arrays(user, data)
      user_update = true
    else
      user = data
    end

    if not user["id"] then
      user["id"] = uuid.generate_random()
    end

    local api_key = user["api_key"]
    user["api_key"] = nil
    if not user["api_key_hash"] then
      if not api_key then
        api_key = random_token(40)
      end
      user["api_key_hash"] = hmac(api_key)
      local encrypted, iv = encryptor.encrypt(api_key, user["id"])
      user["api_key_encrypted"] = encrypted
      user["api_key_encrypted_iv"] = iv
      user["api_key_prefix"] = api_key_prefixer(api_key)
    end

    local roles = user["roles"]
    user["roles"] = nil
    user["cached_api_role_ids"] = nil

    local settings_data = user["settings"]
    user["settings"] = nil

    if user_update then
      local update_result, update_err = pg_utils.update("api_users", { id = user["id"] }, user)
      if not update_result then
        ngx.log(ngx.ERR, "failed to update record in api_users: ", update_err)
        break
      end
    else
      local insert_result, insert_err = pg_utils.insert("api_users", user)
      if not insert_result then
        ngx.log(ngx.ERR, "failed to create record in api_users: ", insert_err)
        break
      end
    end

    if roles then
      for _, role in ipairs(roles) do
        local insert_result, insert_err = pg_utils.query("INSERT INTO api_roles(id) VALUES(:role) ON CONFLICT DO NOTHING", { role = role })
        if not insert_result then
          ngx.log(ngx.ERR, "failed to create record in api_roles: ", insert_err)
          break
        end

        insert_result, insert_err = pg_utils.query("INSERT INTO api_users_roles(api_user_id, api_role_id) VALUES(:api_user_id, :api_role_id) ON CONFLICT DO NOTHING", { api_user_id = user["id"], api_role_id = role })
        if not insert_result then
          ngx.log(ngx.ERR, "failed to create record in api_users_roles: ", insert_err)
          break
        end
      end

      local delete_result, delete_err = pg_utils.query("DELETE FROM api_users_roles WHERE api_user_id = :api_user_id AND api_role_id NOT IN :api_role_ids", { api_user_id = user["id"], api_role_ids = pg_utils.list(roles) })
      if not delete_result then
        ngx.log(ngx.ERR, "failed to delete records in api_users_roles: ", delete_err)
        break
      end
    else
      local delete_result, delete_err = pg_utils.query("DELETE FROM api_users_roles WHERE api_user_id = :api_user_id", { api_user_id = user["id"] })
      if not delete_result then
        ngx.log(ngx.ERR, "failed to delete records in api_users_roles: ", delete_err)
        break
      end
    end

    if settings_data then
      local settings_result, settings_err = pg_utils.query("SELECT * FROM api_user_settings WHERE api_user_id = :api_user_id", { api_user_id = user["id"] })
      if not settings_result then
        ngx.log(ngx.ERR, "failed to query api_user_settings: ", settings_err)
        break
      end

      local settings = settings_result[1]
      local settings_update = false
      if settings then
        settings_update = true
        deep_merge_overwrite_arrays(settings, settings_data)
      else
        settings = settings_data
      end

      if not settings["id"] then
        settings["id"] = uuid.generate_random()
      end
      settings["api_user_id"] = user["id"]

      local rate_limits_data = settings["rate_limits"]
      settings["rate_limits"] = nil

      if settings_update then
        local update_result, update_err = pg_utils.update("api_user_settings", { id = settings["id"] }, settings)
        if not update_result then
          ngx.log(ngx.ERR, "failed to update record in api_user_settings: ", update_err)
          break
        end
      else
        local insert_result, insert_err = pg_utils.insert("api_user_settings", settings)
        if not insert_result then
          ngx.log(ngx.ERR, "failed to create record in api_user_settings: ", insert_err)
          break
        end
      end

      pg_utils.delete("rate_limits", { api_user_settings_id = assert(settings["id"]) })
      if rate_limits_data then
        for _, rate_limit in ipairs(rate_limits_data) do
          rate_limit["id"] = uuid.generate_random()
          rate_limit["api_user_settings_id"] = settings["id"]
          local insert_result, insert_err = pg_utils.insert("rate_limits", rate_limit)
          if not insert_result then
            ngx.log(ngx.ERR, "failed to create record in api_user_settings: ", insert_err)
            break
          end
        end
      end
    else
      pg_utils.delete("api_user_settings", { api_user_id = assert(user["id"]) })
    end

    pg_utils.query("COMMIT")
  end
end

local function seed_initial_superusers()
  for _, username in ipairs(config["web"]["admin"]["initial_superusers"]) do
    pg_utils.query("START TRANSACTION")
    set_stamping()

    local result, admin_err = pg_utils.query("SELECT * FROM admins WHERE username = :username LIMIT 1", { username = username })
    if not result then
      ngx.log(ngx.ERR, "failed to query admins: ", admin_err)
      break
    end

    local data = {
      username = username,
      superuser = true,
    }

    local admin = result[1]
    if admin then
      deep_merge_overwrite_arrays(admin, data)
    else
      admin = data
    end

    if not admin["id"] then
      admin["id"] = uuid.generate_random()
    end
    if not admin["authentication_token_hash"] then
      local authentication_token = random_token(40)
      admin["authentication_token_hash"] = hmac(authentication_token)
      local encrypted, iv = encryptor.encrypt(authentication_token, admin["id"])
      admin["authentication_token_encrypted"] = encrypted
      admin["authentication_token_encrypted_iv"] = iv
    end

    if result[1] then
      local update_result, update_err = pg_utils.update("admins", { id = admin["id"] }, admin)
      if not update_result then
        ngx.log(ngx.ERR, "failed to update record in admins: ", update_err)
      end
    else
      local insert_result, insert_err = pg_utils.insert("admins", admin)
      if not insert_result then
        ngx.log(ngx.ERR, "failed to create record in admins: ", insert_err)
      end
    end

    pg_utils.query("COMMIT")
  end
end

local function seed_admin_permissions()
  local permissions = {
    {
      id = "analytics",
      name = "Analytics",
      display_order = 1,
    },
    {
      id = "user_view",
      name = "API Users - View",
      display_order = 2,
    },
    {
      id = "user_manage",
      name = "API Users - Manage",
      display_order = 3,
    },
    {
      id = "admin_view",
      name = "Admin Accounts - View",
      display_order = 4,
    },
    {
      id = "admin_manage",
      name = "Admin Accounts - Manage",
      display_order = 5,
    },
    {
      id = "backend_manage",
      name = "API Backend Configuration - View & Manage",
      display_order = 6,
    },
    {
      id = "backend_publish",
      name = "API Backend Configuration - Publish",
      display_order = 7,
    },
  }

  for _, data in ipairs(permissions) do
    pg_utils.query("START TRANSACTION")
    set_stamping()

    local result, permission_err = pg_utils.query("SELECT * FROM admin_permissions WHERE id = :id LIMIT 1", { id = data["id"] })
    if not result then
      ngx.log(ngx.ERR, "failed to query admin_permissions: ", permission_err)
      break
    end

    local permission = result[1]
    if permission then
      deep_merge_overwrite_arrays(permission, data)
    else
      permission = data
    end

    if result[1] then
      local update_result, update_err = pg_utils.update("admin_permissions", { id = permission["id"] }, permission)
      if not update_result then
        ngx.log(ngx.ERR, "failed to update record in admin_permissions: ", update_err)
      end
    else
      local insert_result, insert_err = pg_utils.insert("admin_permissions", permission)
      if not insert_result then
        ngx.log(ngx.ERR, "failed to create record in admin_permissions: ", insert_err)
      end
    end

    pg_utils.query("COMMIT")
  end
end

local function seed_dev_api_backend()
  if config["app_env"] ~= "development" then
    return
  end

  local backend_name = "HTTPBin Echo API (Dev)"

  pg_utils.query("START TRANSACTION")
  set_stamping()

  local result, backend_err = pg_utils.query("SELECT * FROM api_backends WHERE name = :name LIMIT 1", { name = backend_name })
  if not result then
    ngx.log(ngx.ERR, "failed to query api_backends: ", backend_err)
    return
  end

  local backend_id
  if result[1] then
    backend_id = result[1]["id"]
  else
    backend_id = uuid.generate_random()

    local insert_result, insert_err = pg_utils.insert("api_backends", {
      id = backend_id,
      name = backend_name,
      backend_protocol = "https",
      frontend_host = "localhost",
      backend_host = "httpbin.org",
      balance_algorithm = "least_conn",
      organization_name = "Development",
      status_description = "Development testing backend",
    })
    if not insert_result then
      ngx.log(ngx.ERR, "failed to create record in api_backends: ", insert_err)
      return
    end

    insert_result, insert_err = pg_utils.insert("api_backend_servers", {
      id = uuid.generate_random(),
      api_backend_id = backend_id,
      host = "httpbin.org",
      port = 443,
    })
    if not insert_result then
      ngx.log(ngx.ERR, "failed to create record in api_backend_servers: ", insert_err)
      return
    end

    insert_result, insert_err = pg_utils.insert("api_backend_url_matches", {
      id = uuid.generate_random(),
      api_backend_id = backend_id,
      frontend_prefix = "/echo/",
      backend_prefix = "/",
    })
    if not insert_result then
      ngx.log(ngx.ERR, "failed to create record in api_backend_url_matches: ", insert_err)
      return
    end
  end

  pg_utils.query("COMMIT")

  -- Publish the backend so it's immediately active
  pg_utils.query("START TRANSACTION")
  set_stamping()

  local published_result, published_err = pg_utils.query("SELECT * FROM published_config ORDER BY id DESC LIMIT 1")
  if not published_result then
    ngx.log(ngx.ERR, "failed to query published_config: ", published_err)
    return
  end

  local current_config = {}
  if published_result[1] and published_result[1]["config"] then
    current_config = published_result[1]["config"]
  end
  if not current_config["apis"] then
    current_config["apis"] = {}
  end
  if not current_config["website_backends"] then
    current_config["website_backends"] = {}
  end

  local already_published = false
  for _, api in ipairs(current_config["apis"]) do
    if api["id"] == backend_id then
      already_published = true
      break
    end
  end

  if not already_published then
    table.insert(current_config["apis"], {
      id = backend_id,
      name = backend_name,
      backend_protocol = "https",
      frontend_host = "localhost",
      backend_host = "httpbin.org",
      balance_algorithm = "least_conn",
      organization_name = "Development",
      status_description = "Development testing backend",
      servers = {
        {
          host = "httpbin.org",
          port = 443,
        },
      },
      url_matches = {
        {
          frontend_prefix = "/echo/",
          backend_prefix = "/",
        },
      },
    })

    local insert_result, insert_err = pg_utils.query(
      "INSERT INTO published_config (config) VALUES (:config)",
      { config = db_raw(pg_encode_json(current_config)) }
    )
    if not insert_result then
      ngx.log(ngx.ERR, "failed to create record in published_config: ", insert_err)
    end
  end

  pg_utils.query("COMMIT")
end

local function seed()
  local _, err = wait_for_postgres()
  if err then
    ngx.log(ngx.ERR, "timed out waiting for postgres before seeding, rerunning...")
    sleep(5)
    return seed()
  end

  seed_api_keys()
  seed_initial_superusers()
  seed_admin_permissions()
  seed_dev_api_backend()
end

local _M = {}

function _M.seed_once()
  interval_lock.mutex_exec("seed_database", seed)
end

function _M.spawn()
  local ok, err = timer_at(0, _M.seed_once)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
    return
  end
end

return _M

local ApiScope = require "api-umbrella.web-app.models.api_scope"
local admin_group_policy = require "api-umbrella.web-app.policies.admin_group_policy"
local admin_policy = require "api-umbrella.web-app.policies.admin_policy"
local api_backend_policy = require "api-umbrella.web-app.policies.api_backend_policy"
local bcrypt = require "bcrypt"
local config = require("api-umbrella.utils.load_config")()
local db = require "lapis.db"
local encryptor = require "api-umbrella.utils.encryptor"
local escape_db_like = require "api-umbrella.utils.escape_db_like"
local hmac = require "api-umbrella.utils.hmac"
local invert_table = require "api-umbrella.utils.invert_table"
local is_empty = require "api-umbrella.utils.is_empty"
local json_array_fields = require "api-umbrella.web-app.utils.json_array_fields"
local json_null = require("cjson").null
local json_null_default = require "api-umbrella.web-app.utils.json_null_default"
local model_ext = require "api-umbrella.web-app.utils.model_ext"
local random_token = require "api-umbrella.utils.random_token"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local time = require "api-umbrella.utils.time"
local username_label = require "api-umbrella.web-app.utils.username_label"
local validation_ext = require "api-umbrella.web-app.utils.validation_ext"

local db_null = db.NULL
local validate_field = model_ext.validate_field
local validate_uniqueness = model_ext.validate_uniqueness

local function username_field_name()
  if config["web"]["admin"]["username_is_email"] then
    return "email"
  else
    return "username"
  end
end

local function validate_email(_, data, errors)
  validate_field(errors, data, "username", username_label(), {
    { validation_ext.string:minlen(1), t("can't be blank") },
    { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
  }, { error_field = username_field_name() })

  if config["web"]["admin"]["username_is_email"] then
    validate_field(errors, data, "username", username_label(), {
      { validation_ext.db_null_optional:regex(config["web"]["admin"]["email_regex"], "jo"), t("is invalid") },
    }, { error_field = username_field_name() })
  else
    validate_field(errors, data, "email", t("Email"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
      { validation_ext.db_null_optional:regex(config["web"]["admin"]["email_regex"], "jo"), t("is invalid") },
    })
  end
end

local function validate_groups(_, data, errors)
  if data["superuser"] ~= true then
    validate_field(errors, data, "group_ids", t("Groups"), {
      { validation_ext.non_null_table:minlen(1), t("must belong to at least one group or be a superuser") },
    }, { error_field = "groups" })
  end
end

local function validate_password(self, data, errors)
  local is_password_required = false
  if not is_empty(data["password"]) and data["password"] ~= db_null then
    is_password_required = true
  elseif not is_empty(data["password_confirmation"]) and data["password_confirmation"] ~= db_null then
    is_password_required = true
  end

  if is_password_required then
    local password_length_min = config["web"]["admin"]["password_length_min"]
    local password_length_max = config["web"]["admin"]["password_length_max"]
    validate_field(errors, data, "password", t("Password"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.db_null_optional.string:minlen(password_length_min), string.format(t("is too short (minimum is %d characters)"), password_length_min) },
      { validation_ext.db_null_optional.string:maxlen(password_length_max), string.format(t("is too long (maximum is %d characters)"), password_length_max) },
    })
    validate_field(errors, data, "password_confirmation", t("Password confirmation"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.db_null_optional.string:equals(data["password"]), t("doesn't match Password") },
    })

    if self and self.id and not self._reset_password_mode then
      validate_field(errors, data, "current_password", t("Current password"), {
        { validation_ext.string:minlen(1), t("can't be blank") },
      })
      if not is_empty(data["current_password"]) and data["current_password"] ~= db_null then
        if not self:is_valid_password(data["current_password"]) then
          model_ext.add_error(errors, "current_password", t("Current password"), t("is invalid"))
        end
      end
    end
  end
end

local Admin
Admin = model_ext.new_class("admins", {
  relations = {
    model_ext.has_and_belongs_to_many("groups", "AdminGroup", {
      join_table = "admin_groups_admins",
      foreign_key = "admin_id",
      association_foreign_key = "admin_group_id",
      order = "name",
    }),
    model_ext.has_and_belongs_to_many("authorized_groups", "AdminGroup", {
      join_table = "admin_groups_admins",
      foreign_key = "admin_id",
      association_foreign_key = "admin_group_id",
      order = "name",
      transform_sql = function(sql)
        local scope_sql = admin_group_policy.authorized_query_scope(ngx.ctx.current_admin)
        if scope_sql then
          return string.gsub(sql, " WHERE ", " WHERE " .. scope_sql .. " AND ", 1)
        else
          return sql
        end
      end,
    }),
  },

  attributes = function(self, options)
    if not options then
      options = {
        includes = {
          groups = {},
        },
      }
    end

    return model_ext.record_attributes(self, options)
  end,

  authorize = function(self)
    admin_policy.authorize_show(ngx.ctx.current_admin, self:attributes())
  end,

  is_valid_password = function(self, password)
    if self.password_hash and password and bcrypt.verify(password, self.password_hash) then
      return true
    else
      return false
    end
  end,

  is_access_locked = function(self)
    if self.locked_at and not self:is_lock_expired() then
      return true
    else
      return false
    end
  end,

  is_lock_expired = function(self)
    local expired = false
    if self.locked_at then
      expired = true
      local unlock_at = ngx.now() - 2 * 60 * 60
      if time.postgres_to_timestamp(self.locked_at) < unlock_at then
        expired = false
      end
    end

    return expired
  end,

  is_reset_password_expired = function(self)
    local expired = false
    if self.reset_password_sent_at then
      expired = true
      local expires_at = ngx.now() - 6 * 60 * 60
      if time.postgres_to_timestamp(self.reset_password_sent_at) > expires_at then
        expired = false
      end
    end

    return expired
  end,

  authentication_token_decrypted = function(self)
    local decrypted
    if self.authentication_token_encrypted and self.authentication_token_encrypted_iv then
      decrypted = encryptor.decrypt(self.authentication_token_encrypted, self.authentication_token_encrypted_iv, self.id)
    end

    return decrypted
  end,

  authorized_group_ids = function(self)
    local authorized_group_ids = {}
    local groups = self:get_authorized_groups()
    for _, group in ipairs(groups) do
      table.insert(authorized_group_ids, group.id)
    end

    return authorized_group_ids
  end,

  authorized_group_names = function(self)
    local authorized_group_names = {}
    for _, group in ipairs(self:get_authorized_groups()) do
      table.insert(authorized_group_names, group.name)
    end
    if self.superuser then
      table.insert(authorized_group_names, t("Superuser"))
    end

    return authorized_group_names
  end,

  group_permission_ids = function(self)
    if not self._group_permission_ids then
      self._group_permission_ids = {}

      local rows = db.query([[
        SELECT DISTINCT admin_groups_admin_permissions.admin_permission_id
        FROM admin_groups_admin_permissions
          INNER JOIN admin_groups_admins ON admin_groups_admin_permissions.admin_group_id = admin_groups_admins.admin_group_id
        WHERE admin_groups_admins.admin_id = ?]], self.id)
      for _, row in ipairs(rows) do
        table.insert(self._group_permission_ids, row["admin_permission_id"])
      end
    end

    return self._group_permission_ids
  end,

  group_permission_ids_lookup = function(self)
    if not self._group_permission_ids_lookup then
      self._group_permission_ids_lookup = invert_table(self:group_permission_ids())
    end

    return self._group_permission_ids_lookup
  end,

  allows_permission = function(self, permission_id)
    assert(permission_id)

    if self.superuser then
      return true
    end

    local permission_ids = self:group_permission_ids_lookup()
    if permission_ids[permission_id] then
      return true
    end

    return false
  end,

  authorized_groups_as_json = function(self)
    local admin_groups = {}
    for _, admin_group in ipairs(self:get_authorized_groups()) do
      table.insert(admin_groups, admin_group:embedded_json())
    end

    return admin_groups
  end,

  as_json = function(self, options)
    local data = {
      id = json_null_default(self.id),
      username = json_null_default(self.username),
      email = json_null_default(self.email),
      name = json_null_default(self.name),
      superuser = json_null_default(self.superuser),
      current_sign_in_provider = json_null_default(self.current_sign_in_provider),
      last_sign_in_provider = json_null_default(self.last_sign_in_provider),
      reset_password_sent_at = json_null_default(time.postgres_to_iso8601(self.reset_password_sent_at)),
      sign_in_count = json_null_default(self.sign_in_count),
      current_sign_in_at = json_null_default(time.postgres_to_iso8601(self.current_sign_in_at)),
      last_sign_in_at = json_null_default(time.postgres_to_iso8601(self.last_sign_in_at)),
      current_sign_in_ip = json_null_default(self.current_sign_in_ip),
      last_sign_in_ip = json_null_default(self.last_sign_in_ip),
      failed_attempts = json_null_default(self.failed_attempts),
      locked_at = json_null_default(time.postgres_to_iso8601(self.locked_at)),
      created_at = json_null_default(time.postgres_to_iso8601(self.created_at)),
      created_by = json_null_default(self.created_by_id),
      creator = {
        username = json_null_default(self.created_by_username),
      },
      updated_at = json_null_default(time.postgres_to_iso8601(self.updated_at)),
      updated_by = json_null_default(self.updated_by_id),
      updater = {
        username = json_null_default(self.updated_by_username),
      },
      groups = json_null_default(self:authorized_groups_as_json()),
      group_ids = json_null_default(self:authorized_group_ids()),
      group_names = json_null_default(self:authorized_group_names()),
      deleted_at = json_null,
      version = 1,
    }

    local current_admin = ngx.ctx.current_admin
    if current_admin and current_admin:allows_permission("admin_manage") then
      data["notes"] = json_null_default(self.notes)
    end

    if current_admin and current_admin.id == self.id then
      data["authentication_token"] = self:authentication_token_decrypted()
    end

    json_array_fields(data, {
      "groups",
      "group_ids",
      "group_names",
    }, options)

    return data
  end,

  csv_headers = function()
    return {
      username_label(),
      t("Groups"),
      t("Last Signed In"),
      t("Created"),
    }
  end,

  as_csv = function(self)
    return {
      json_null_default(self.username),
      json_null_default(table.concat(self:authorized_group_names(), "\n")),
      json_null_default(time.postgres_to_iso8601(self.current_sign_in_at)),
      json_null_default(time.postgres_to_iso8601(self.created_at)),
    }
  end,

  set_reset_password_token = function(self, override_sent_at)
    local token = random_token(24, true)
    local token_hash = hmac(token)
    model_ext.transaction_update("admins", {
      reset_password_token_hash = token_hash,
      reset_password_sent_at = override_sent_at or db.raw("now() AT TIME ZONE 'UTC'"),
    }, { id = assert(self.id) })
    self:refresh()

    return token
  end,

  -- Use set_reset_password_token, but set the reset_password_sent_at date 2
  -- weeks into the future. This allows for the normal reset password valid
  -- period to be shorter (6 hours), but we can leverage the same reset
  -- password process for the initial invite where we want the period to be
  -- longer.
  set_invite_reset_password_token = function(self)
    return self:set_reset_password_token(db.raw("(now() + interval '2 weeks') AT TIME ZONE 'UTC'"))
  end,

  api_scopes = function(self)
    return ApiScope:load_all(db.query([[
      SELECT DISTINCT api_scopes.*
      FROM api_scopes
        INNER JOIN admin_groups_api_scopes ON api_scopes.id = admin_groups_api_scopes.api_scope_id
        INNER JOIN admin_groups_admins ON admin_groups_api_scopes.admin_group_id = admin_groups_admins.admin_group_id
      WHERE admin_groups_admins.admin_id = ?]], self.id))
  end,

  -- Fetch all the API scopes this admin belongs to (through their group
  -- membership) that has a certain permission.
  api_scopes_with_permission = function(self, permission_id)
    if type(permission_id) == "string" then
      permission_id = { permission_id }
    end

    return ApiScope:load_all(db.query([[
      SELECT DISTINCT api_scopes.*
      FROM api_scopes
        INNER JOIN admin_groups_api_scopes ON api_scopes.id = admin_groups_api_scopes.api_scope_id
        INNER JOIN admin_groups_admin_permissions ON admin_groups_api_scopes.admin_group_id = admin_groups_admin_permissions.admin_group_id
        INNER JOIN admin_groups_admins ON admin_groups_api_scopes.admin_group_id = admin_groups_admins.admin_group_id
      WHERE admin_groups_admins.admin_id = ?
        AND admin_groups_admin_permissions.admin_permission_id IN ?]], self.id, db.list(permission_id)))
  end,

  -- Fetch all the API scopes this admin belongs to that has a certain
  -- permission. Differing from #api_scopes_with_permission, this also includes
  -- any nested duplicative scopes.
  --
  -- For example, if the user were explicitly granted permissions on a
  -- "api.example.com/" scope, this would also return any other sub-scopes that
  -- might exist, like "api.example.com/foo" (even if the admin account didn't
  -- have explicit permissions on that scope). This can be useful when needing
  -- a full list of scope IDs that the admin can operate on (since our prefix
  -- based approach means there might be other scopes that exist, but haven't
  -- been explicitly granted permissions to).
  nested_api_scopes_with_permission = function(self, permission_id)
    local api_scopes = self:api_scopes_with_permission(permission_id)
    if is_empty(api_scopes) then
      return api_scopes
    end

    local query = {}
    for _, api_scope in ipairs(api_scopes) do
      table.insert(query, db.interpolate_query("(host = ? AND path_prefix LIKE ? || '%')",api_scope.host, escape_db_like(api_scope.path_prefix)))
    end

    return ApiScope:select("WHERE " .. table.concat(query, " OR "))
  end,

  nested_api_scope_ids_with_permission = function(self, permission_id)
    local api_scope_ids = {}
    local api_scopes = self:nested_api_scopes_with_permission(permission_id)
    for _, api_scope in ipairs(api_scopes) do
      table.insert(api_scope_ids, api_scope.id)
    end

    return api_scope_ids
  end,

  disallowed_role_ids = function(self)
    if not self._disallowed_role_ids then
      self._disallowed_role_ids = {}
      local scope = api_backend_policy.authorized_query_scope(self, { "user_manage", "backend_manage" })
      if scope then
        local rows = db.query([[
          WITH allowed_api_backends AS (
            SELECT id FROM api_backends
            WHERE ]] .. scope .. [[
          )
          SELECT r.api_role_id
          FROM api_backend_settings_required_roles AS r
            LEFT JOIN api_backend_settings AS s ON r.api_backend_settings_id = s.id
            LEFT JOIN api_backend_sub_url_settings AS sub ON s.api_backend_sub_url_settings_id = sub.id
            LEFT JOIN allowed_api_backends AS b ON s.api_backend_id = b.id OR sub.api_backend_id = b.id
          WHERE b.id IS NULL
        ]])
        for _, row in ipairs(rows) do
          table.insert(self._disallowed_role_ids, row["api_role_id"])
        end
      end
    end

    return self._disallowed_role_ids
  end,
}, {
  authorize = function(data)
    admin_policy.authorize_modify(ngx.ctx.current_admin, data)
  end,

  before_validate_on_create = function(_, values)
    local authentication_token = random_token(40, true)
    values["authentication_token_hash"] = hmac(authentication_token)
    local encrypted, iv = encryptor.encrypt(authentication_token, values["id"])
    values["authentication_token_encrypted"] = encrypted
    values["authentication_token_encrypted_iv"] = iv
  end,

  before_validate = function(_, values)
    if values["superuser"] then
      -- For backwards compatibility (with how Mongoid parsed booleans), accept
      -- some alternate values for true.
      if values["superuser"] == true or values["superuser"] == 1 or values["superuser"] == "1" or values["superuser"] == "true" then
        values["superuser"] = true
      else
        values["superuser"] = false
      end
    end

    if config["web"]["admin"]["username_is_email"] and values["username"] then
      values["email"] = values["username"]
    end

    if type(values["email"]) == "string" then
      values["email"] = string.lower(values["email"])
    end

    if type(values["username"]) == "string" then
      values["username"] = string.lower(values["username"])
    end
  end,

  validate = function(self, data)
    local errors = {}
    validate_email(self, data, errors)
    validate_groups(self, data, errors)
    validate_password(self, data, errors)
    validate_field(errors, data, "name", t("Name"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    })
    validate_field(errors, data, "superuser", t("Superuser"), {
      { validation_ext.db_null_optional.boolean, t("can't be blank") },
    })
    validate_uniqueness(errors, data, "username", t("Username"), Admin, { "username" })
    return errors
  end,

  after_validate = function(_, values)
    if not is_empty(values["password"]) then
      values["password_hash"] = bcrypt.digest(values["password"], 11)
    end
  end,

  after_save = function(self, values)
    model_ext.save_has_and_belongs_to_many(self, values["group_ids"], {
      join_table = "admin_groups_admins",
      foreign_key = "admin_id",
      association_foreign_key = "admin_group_id",
    })
  end,
})

Admin.needs_first_account = function()
  local needs = false
  if config["web"]["admin"]["auth_strategies"]["_enabled"]["local"] and Admin:count() == 0 then
    needs = true
  end

  return needs
end

Admin.find_by_reset_password_token = function(_, token)
  if is_empty(token) then
    return nil
  end

  local token_hash = hmac(token)
  return Admin:find({ reset_password_token_hash = token_hash })
end

Admin.find_for_login = function(_, username)
  local admin
  if not is_empty(username) then
    admin = Admin:find({ username = string.lower(username) })
    if admin and admin:is_access_locked() then
      admin = nil
    end
  end

  return admin
end

return Admin

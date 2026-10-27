local ApiRole = require "api-umbrella.web-app.models.api_role"
local ApiUserSettings = require "api-umbrella.web-app.models.api_user_settings"
local api_key_prefixer = require("api-umbrella.utils.api_key_prefixer").prefix
local api_user_policy = require "api-umbrella.web-app.policies.api_user_policy"
local array_includes = require "api-umbrella.utils.array_includes"
local cjson = require "cjson"
local config = require("api-umbrella.utils.load_config")()
local db = require "lapis.db"
local encryptor = require "api-umbrella.utils.encryptor"
local hmac = require "api-umbrella.utils.hmac"
local is_array = require "api-umbrella.utils.is_array"
local is_hash = require "api-umbrella.utils.is_hash"
local json_array_fields = require "api-umbrella.web-app.utils.json_array_fields"
local json_encode = require "api-umbrella.utils.json_encode"
local json_null_default = require "api-umbrella.web-app.utils.json_null_default"
local lyaml = require "lyaml"
local model_ext = require "api-umbrella.web-app.utils.model_ext"
local nillify_yaml_nulls = require "api-umbrella.utils.nillify_yaml_nulls"
local pg_encode_array = require "api-umbrella.utils.pg_encode_array"
local pg_encode_json = require("pgmoon.json").encode_json
local pretty_yaml_dump = require "api-umbrella.web-app.utils.pretty_yaml_dump"
local random_token = require "api-umbrella.utils.random_token"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local time = require "api-umbrella.utils.time"
local validation_ext = require "api-umbrella.web-app.utils.validation_ext"

local db_null = db.NULL
local db_raw = db.raw
local json_null = cjson.null
local validate_field = model_ext.validate_field

local ApiUser
ApiUser = model_ext.new_class("api_users", {
  relations = {
    { "settings", has_one = "ApiUserSettings" },
    model_ext.has_and_belongs_to_many("roles", "ApiRole", {
      join_table = "api_users_roles",
      foreign_key = "api_user_id",
      association_foreign_key = "api_role_id",
      order = "id",
    }),
  },

  attributes = function(self, options)
    if not options then
      options = {
        includes = {
          roles = {},
          settings = {
            includes = {
              rate_limits = {},
            },
          },
        },
      }
    end

    return model_ext.record_attributes(self, options)
  end,

  authorize = function(self)
    api_user_policy.authorize_show(ngx.ctx.current_admin, self:attributes())
  end,

  api_key_decrypted = function(self)
    local decrypted
    if self.api_key_encrypted and self.api_key_encrypted_iv then
      decrypted = encryptor.decrypt(self.api_key_encrypted, self.api_key_encrypted_iv, self.id)
    end

    return decrypted
  end,

  api_key_preview = function(self)
    local preview
    if self.api_key_prefix then
      preview = string.sub(self.api_key_prefix, 1, 6) .. "..."
    end

    return preview
  end,

  api_key_hides_at = function(self)
    if not self._api_key_hides_at then
      local hides_at = time.postgres_to_timestamp(self.created_at)
      self._api_key_hides_at = hides_at
    end

    return self._api_key_hides_at
  end,

  admin_can_view_api_key = function(self)
    local allowed = false

    local current_admin = ngx.ctx.current_admin
    if current_admin then
      if current_admin.superuser then
        allowed = true
      elseif self.created_by_id and self.created_by_id == current_admin.id then
        allowed = true
      end
    end

    return allowed
  end,

  role_ids = function(self)
    local role_ids = {}
    for _, role in ipairs(self:get_roles()) do
      table.insert(role_ids, role.id)
    end

    return role_ids
  end,

  enabled = function(self)
    if self.disabled_at then
      return false
    else
      return true
    end
  end,

  metadata_yaml_string = function(self)
    if not self._metadata_yaml_string and self.metadata then
      self._metadata_yaml_string = pretty_yaml_dump(self.metadata)
    end

    return self._metadata_yaml_string
  end,

  as_json = function(self, options)
    local updated_at = time.postgres_to_timestamp(self.updated_at)
    local data = {
      id = json_null_default(self.id),
      email = json_null_default(self.email),
      first_name = json_null_default(self.first_name),
      last_name = json_null_default(self.last_name),
      use_description = json_null_default(self.use_description),
      website = json_null_default(self.website),
      registration_source = json_null_default(self.registration_source),
      throttle_by_ip = json_null_default(self.throttle_by_ip),
      roles = json_null_default(self:role_ids()),
      settings = json_null,
      enabled = self:enabled(),
      disabled_at = json_null_default(time.postgres_to_iso8601(self.disabled_at)),
      ts = {
        ["$timestamp"] = {
          t = json_null_default(math.floor(updated_at)),
          i = 1,
        },
      },
      created_at = json_null_default(time.postgres_to_iso8601(self.created_at)),
      created_by = json_null_default(self.created_by_id),
      creator = {
        username = json_null_default(self.created_by_username),
      },
      updated_at = json_null_default(time.timestamp_to_iso8601(updated_at)),
      updated_by = json_null_default(self.updated_by_id),
      updater = {
        username = json_null_default(self.updated_by_username),
      },
      deleted_at = json_null,
      version = 1,
    }

    if ngx.ctx.current_admin then
      data["api_key_preview"] = json_null_default(self:api_key_preview())
      data["email_verified"] = json_null_default(self.email_verified)
      data["registration_ip"] = json_null_default(self.registration_ip)
      data["registration_origin"] = json_null_default(self.registration_origin)
      data["registration_referer"] = json_null_default(self.registration_referer)
      data["registration_user_agent"] = json_null_default(self.registration_user_agent)
      data["registration_key_creator_api_user_id"] = json_null_default(self.registration_key_creator_api_user_id)
      data["metadata"] = json_null_default(self.metadata)
      data["metadata_yaml_string"] = json_null_default(self:metadata_yaml_string())

      if options and options["allow_api_key"] and self:admin_can_view_api_key() then
        data["api_key"] = json_null_default(self:api_key_decrypted())
        data["api_key_hides_at"] = json_null_default(time.timestamp_to_iso8601(self:api_key_hides_at()))
      end
    end

    local settings = self:get_settings()
    if settings then
      data["settings"] = settings:as_json(options)

      -- Add legacy "_id" fields on the embedded rate limits.
      --
      -- We never intended to return this (everything else returns just "id"),
      -- but we accidentally included "_id" on the "show" endpoint for API
      -- users. So keep returning for backwards compatibility, but should
      -- remove for V2 of APIs.
      if data["settings"]["rate_limits"] then
        for _, rate_limit in ipairs(data["settings"]["rate_limits"]) do
          rate_limit["_id"] = rate_limit["id"]
        end
      end
    end

    json_array_fields(data, {"roles"}, options)

    return data
  end,

  csv_headers = function()
    local headers = {
      t("E-mail"),
      t("First Name"),
      t("Last Name"),
      t("Purpose"),
      t("Created"),
      t("Registration Source"),
    }

    if ngx.ctx.current_admin then
      table.insert(headers, t("API Key"))
    end

    return headers
  end,

  as_csv = function(self)
    local data = {
      json_null_default(self.email),
      json_null_default(self.first_name),
      json_null_default(self.last_name),
      json_null_default(self.use_description),
      json_null_default(time.postgres_to_iso8601(self.created_at)),
      json_null_default(self.registration_source),
    }

    if ngx.ctx.current_admin then
      table.insert(data, json_null_default(self:api_key_preview()))
    end

    return data
  end,

  settings_update_or_create = function(self, settings_values)
    return model_ext.has_one_update_or_create(self, ApiUserSettings, "api_user_id", settings_values)
  end,

  settings_delete = function(self)
    return model_ext.has_one_delete(self, ApiUserSettings, "api_user_id")
  end,
}, {
  authorize = function(data, action)
    if action == "create" then
      api_user_policy.authorize_create(ngx.ctx.current_admin, data)
    else
      api_user_policy.authorize_modify(ngx.ctx.current_admin, data)
    end
  end,

  before_validate_on_create = function(_, values)
    local api_key = random_token(40, true)
    values["api_key_hash"] = hmac(api_key)
    local encrypted, iv = encryptor.encrypt(api_key, values["id"])
    values["api_key_encrypted"] = encrypted
    values["api_key_encrypted_iv"] = iv
    values["api_key_prefix"] = api_key_prefixer(api_key)
  end,

  before_validate = function(_, values)
    local enabled = tostring(values["enabled"])
    if enabled == "true" then
      values["disabled_at"] = db_null
    elseif enabled == "false" and not values["disabled_at"] then
      values["disabled_at"] = db.raw("now() AT TIME ZONE 'UTC'")
    end

    local terms_and_conditions = tostring(values["terms_and_conditions"])
    if terms_and_conditions == "true" or terms_and_conditions == "1" then
      values["terms_and_conditions"] = true
    elseif values["terms_and_conditions"] and values["terms_and_conditions"] ~= db_null then
      values["terms_and_conditions"] = false
    end

    if values["metadata_yaml_string"] then
      if values["metadata_yaml_string"] == db_null then
        values["metadata"] = db_null
      else
        local ok, field_data = pcall(lyaml.load, values["metadata_yaml_string"])
        if ok then
          if is_hash(field_data) then
            nillify_yaml_nulls(field_data)
          end
          values["metadata"] = field_data
        else
          values["_metadata_yaml_string_parse_error"] = string.format(t("YAML parsing error: %s"), (field_data or ""))
        end
      end
    end
  end,

  validate = function(self, data)
    local errors = {}
    validate_field(errors, data, "first_name", t("First name"), {
      { validation_ext.string:minlen(1), t("Provide your first name.") },
      { validation_ext.string:maxlen(80), string.format(t("is too long (maximum is %d characters)"), 80) },
      { validation_ext.db_null_optional:not_regex(config["web"]["api_user"]["first_name_exclude_regex"], "ijo"), t("is invalid") },
    })
    validate_field(errors, data, "last_name", t("Last name"), {
      { validation_ext.string:minlen(1), t("Provide your last name.") },
      { validation_ext.string:maxlen(80), string.format(t("is too long (maximum is %d characters)"), 80) },
      { validation_ext.db_null_optional:not_regex(config["web"]["api_user"]["last_name_exclude_regex"], "ijo"), t("is invalid") },
    })
    validate_field(errors, data, "email", t("Email"), {
      { validation_ext.string:minlen(1), t("Provide your email address.") },
      { validation_ext.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
      { validation_ext.db_null_optional:regex(config["web"]["api_user"]["email_regex"], "ijo"), t("Provide a valid email address.") },
    })
    validate_field(errors, data, "website", t("Website"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
      { validation_ext.db_null_optional:regex([[\w+\.\w+]], "jo"), t("Your website must be a valid URL in the form of http://example.com") },
    })
    validate_field(errors, data, "use_description", t("How will you use the APIs?"), {
      { validation_ext.db_null_optional.string:maxlen(2000), string.format(t("is too long (maximum is %d characters)"), 2000) },
    })
    validate_field(errors, data, "role_ids", t("Roles"), {
      { validation_ext.db_null_optional.array_table, t("is not an array") },
      { validation_ext.db_null_optional.array_strings, t("must be an array of strings") },
      { validation_ext.db_null_optional:array_strings_maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    }, { error_field = "roles" })
    validate_field(errors, data, "registration_source", t("Registration source"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    })
    validate_field(errors, data, "registration_user_agent", t("Registration user agent"), {
      { validation_ext.db_null_optional.string:maxlen(1000), string.format(t("is too long (maximum is %d characters)"), 1000) },
    })
    validate_field(errors, data, "registration_referer", t("Registration referer"), {
      { validation_ext.db_null_optional.string:maxlen(1000), string.format(t("is too long (maximum is %d characters)"), 1000) },
    })
    validate_field(errors, data, "registration_origin", t("Registration origin"), {
      { validation_ext.db_null_optional.string:maxlen(1000), string.format(t("is too long (maximum is %d characters)"), 1000) },
    })
    validate_field(errors, data, "registration_recaptcha_v2_success", t("CAPTCHA success"), {
      { validation_ext.db_null_optional.boolean, t("is not a boolean") },
    })
    validate_field(errors, data, "registration_recaptcha_v2_hostname", t("CAPTCHA hostname"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    })
    validate_field(errors, data, "registration_recaptcha_v2_error_codes", t("CAPTCHA error codes"), {
      { validation_ext.db_null_optional.array_table, t("is not an array") },
      { validation_ext.db_null_optional.array_strings, t("must be an array of strings") },
      { validation_ext.db_null_optional:array_strings_maxlen(50), string.format(t("is too long (maximum is %d characters)"), 50) },
    })
    validate_field(errors, data, "registration_recaptcha_v3_success", t("CAPTCHA success"), {
      { validation_ext.db_null_optional.boolean, t("is not a boolean") },
    })
    validate_field(errors, data, "registration_recaptcha_v3_hostname", t("CAPTCHA hostname"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    })
    validate_field(errors, data, "registration_recaptcha_v3_score", t("CAPTCHA score"), {
      { validation_ext.db_null_optional.number, t("is not a number") },
    })
    validate_field(errors, data, "registration_recaptcha_v3_action", t("CAPTCHA action"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    })
    validate_field(errors, data, "registration_recaptcha_v3_error_codes", t("CAPTCHA error codes"), {
      { validation_ext.db_null_optional.array_table, t("is not an array") },
      { validation_ext.db_null_optional.array_strings, t("must be an array of strings") },
      { validation_ext.db_null_optional:array_strings_maxlen(50), string.format(t("is too long (maximum is %d characters)"), 50) },
    })

    if not self or not self.id then
      validate_field(errors, data, "terms_and_conditions", t("Terms and conditions"), {
        { validation_ext.boolean:equals(true), t("Check the box to agree to the terms and conditions.") },
      })
    end

    if data["role_ids"] ~= db_null and is_array(data["role_ids"]) and array_includes(data["role_ids"], "api-umbrella-key-creator") and #data["role_ids"] > 1 then
      model_ext.add_error(errors, "role_ids", t("Roles"), t("no other roles can be assigned when the \"api-umbrella-key-creator\" role is present"))
    end

    if data["metadata"] and not is_hash(data["metadata"]) and data["metadata"] ~= db_null then
      model_ext.add_error(errors, "metadata", t("Metadata"), t("unexpected type (must be a hash)"))
    end

    if data["_metadata_yaml_string_parse_error"] then
      model_ext.add_error(errors, "metadata_yaml_string", t("Metadata"), data["_metadata_yaml_string_parse_error"])
    end

    if data["registration_options"] and not is_hash(data["registration_options"]) and data["registration_options"] ~= db_null then
      model_ext.add_error(errors, "registration_options", t("Registration options"), t("unexpected type (must be a hash)"))
    end

    if data["registration_options"] and is_hash(data["registration_options"]) and data["registration_options"] ~= db_null and string.len(json_encode(data["registration_options"])) > 4000 then
      model_ext.add_error(errors, "registration_options", t("Registration options"), t("is too long"))
    end

    if data["registration_input_options"] and not is_hash(data["registration_input_options"]) and data["registration_input_options"] ~= db_null then
      model_ext.add_error(errors, "registration_input_options", t("Registration input options"), t("unexpected type (must be a hash)"))
    end

    if data["registration_input_options"] and is_hash(data["registration_input_options"]) and data["registration_input_options"] ~= db_null and string.len(json_encode(data["registration_input_options"])) > 4000 then
      model_ext.add_error(errors, "registration_input_options", t("Registration input options"), t("is too long"))
    end

    return errors
  end,

  before_save = function(_, values)
    if is_hash(values["metadata"]) and values["metadata"] ~= db_null then
      values["metadata"] = db_raw(pg_encode_json(values["metadata"]))
    end

    if is_array(values["registration_recaptcha_v2_error_codes"]) and values["registration_recaptcha_v2_error_codes"] ~= db_null then
      values["registration_recaptcha_v2_error_codes"] = db_raw(pg_encode_array(values["registration_recaptcha_v2_error_codes"]))
    end

    if is_array(values["registration_recaptcha_v3_error_codes"]) and values["registration_recaptcha_v3_error_codes"] ~= db_null then
      values["registration_recaptcha_v3_error_codes"] = db_raw(pg_encode_array(values["registration_recaptcha_v3_error_codes"]))
    end

    if is_hash(values["registration_options"]) and values["registration_options"] ~= db_null then
      values["registration_options"] = db_raw(pg_encode_json(values["registration_options"]))
    end

    if is_hash(values["registration_input_options"]) and values["registration_input_options"] ~= db_null then
      values["registration_input_options"] = db_raw(pg_encode_json(values["registration_input_options"]))
    end
  end,

  after_save = function(self, values)
    model_ext.has_one_save(self, values, "settings")
    ApiRole.insert_missing(values["role_ids"])
    model_ext.save_has_and_belongs_to_many(self, values["role_ids"], {
      join_table = "api_users_roles",
      foreign_key = "api_user_id",
      association_foreign_key = "api_role_id",
    })
  end,
})

return ApiUser

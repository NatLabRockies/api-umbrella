local ApiUser = require "api-umbrella.web-app.models.api_user"
local api_key_prefixer = require("api-umbrella.utils.api_key_prefixer").prefix
local api_user_policy = require "api-umbrella.web-app.policies.api_user_policy"
local api_user_request_deactivation_mailer = require "api-umbrella.web-app.mailers.api_user_request_deactivation"
local build_url = require "api-umbrella.utils.build_url"
local config = require("api-umbrella.utils.load_config")()
local hmac = require "api-umbrella.utils.hmac"
local is_empty = require "api-umbrella.utils.is_empty"
local model_ext = require "api-umbrella.web-app.utils.model_ext"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local url_build = require "api-umbrella.utils.url_build"
local url_parse = require "api-umbrella.utils.url_parse"
local validation_ext = require "api-umbrella.web-app.utils.validation_ext"

local add_error = model_ext.add_error
local validate_field = model_ext.validate_field

local _M = {}

local function validate(data)
  local errors = {}
  validate_field(errors, data, "api_key", t("API Key"), {
    { validation_ext.string:minlen(40), string.format(t("is too short (minimum is %d characters)"), 40) },
    { validation_ext.db_null_optional.string:maxlen(40), string.format(t("is too long (maximum is %d characters)"), 40) },
  })
  validate_field(errors, data, "email", t("Email"), {
    { validation_ext.string:minlen(1), t("can't be blank") },
    { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    { validation_ext.db_null_optional:regex(config["web"]["api_user"]["email_regex"], "ijo"), t("is invalid") },
  })
  return errors
end

function _M.authorized_deliver(_, data, options)
  api_user_policy.authorize_create(ngx.ctx.current_admin, data)

  local errors = validate(data)
  if not is_empty(errors) then
    return coroutine.yield("error", errors)
  end

  local api_key_prefix = api_key_prefixer(data["api_key"])
  local api_user = ApiUser:find({ email = string.lower(data["email"]), api_key_prefix = api_key_prefix })
  if api_user then
    local api_key_hash = hmac(data["api_key"])
    if api_user.api_key_hash ~= api_key_hash then
      api_user = nil
    end
  end

  if not api_user then
    add_error(errors, "email", t("Email"), t("a matching email and API key could not be found"))
    return coroutine.yield("error", errors)
  end

  if api_user.disabled_at then
    add_error(errors, "api_key", t("API Key"), t("is already deactivated"))
    return coroutine.yield("error", errors)
  end

  local token = api_user:set_deactivation_token()

  local parsed, parse_err
  if options and options["submitted_from_url"] then
    parsed, parse_err = url_parse(options["submitted_from_url"])
    if parse_err then
      ngx.log(ngx.ERR, "error parsing submitted_from_url: ", options["submitted_from_url"], " error: ", parse_err)
    end
  end
  if not parsed then
    parsed, parse_err = url_parse(build_url("/signup/"))
    if parse_err then
      ngx.log(ngx.ERR, "error parsing signup url: ", parse_err)
    end
  end
  parsed["fragment"] = "/confirm-deactivation?" .. ngx.encode_args({
    token = token,
  })
  local url = url_build(parsed)

  local ok, err = api_user_request_deactivation_mailer(api_user, url, parsed["host"])
  -- if not ok then
  --   ngx.log(ngx.ERR, "mail error: ", err)
  --   -- message_level = "danger"
  --   -- message = t("An unexpected error occurred when sending the email.")
  --   return false
  -- else
  --   return true
  -- end

  return api_user
end

return _M

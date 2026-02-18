local hmac = require "api-umbrella.utils.hmac"
local json_encode = require "api-umbrella.utils.json_encode"
local encryptor = require "api-umbrella.utils.encryptor"
local random_token = require "api-umbrella.utils.random_token"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local split = require("ngx.re").split

local _M = {}

-- A CSRF token implementation.
--
-- Note that we're not using the default Lapis CSRF implementation. This
-- implementation integrates a bit more easily with resty-session and the rest
-- of our standard encryption libraries. It also makes generating the token a
-- bit easier, since the token can be generated inside views, rather than
-- having to be generated before (due to ordering of how Lapis sets cookies).

function _M.generate_token(self)
  self:init_session_cookie()
  self.session_cookie:open()
  local csrf_token_key = self.session_cookie:get("csrf_token_key")
  local csrf_token_iv = self.session_cookie:get("csrf_token_iv")
  if not csrf_token_key or not csrf_token_iv then
    if not csrf_token_key then
      csrf_token_key = random_token(40)
      self.session_cookie:set("csrf_token_key", csrf_token_key)
    end

    if not csrf_token_iv then
      csrf_token_iv = random_token(12)
      self.session_cookie:set("csrf_token_iv", csrf_token_iv)
    end

    self.session_cookie:save()
  end

  local auth_data = (ngx.var.http_user_agent or "") .. (ngx.var.scheme or "")
  local encrypted, iv = encryptor.encrypt(csrf_token_key, auth_data, { iv = csrf_token_iv })
  return encrypted .. "|" .. iv
end

local function validate_token(self)
  self:init_session_cookie()
  local ok, open_err = self.session_cookie:open()
  if not ok and open_err and open_err ~= "missing session cookie" then
    ngx.log(ngx.ERR, "session open error: ", open_err)
  end

  local key = self.session_cookie:get("csrf_token_key")
  if not key then
    return false, "Missing CSRF token key"
  end

  local csrf_token = self.params.csrf_token or ngx.var.http_x_csrf_token
  if not csrf_token then
    return false, "Missing CSRF token"
  end

  local parts = split(csrf_token, "\\|")
  if #parts ~= 2 then
    return false, "Unable to extract CSRF token"
  end

  local encrypted = parts[1]
  local iv = parts[2]

  local auth_data = (ngx.var.http_user_agent or "") .. (ngx.var.scheme or "")
  local decrypted, decrypt_err = encryptor.decrypt(encrypted, iv, auth_data)
  if decrypted == key then
    return true
  elseif decrypt_err then
    return false, decrypt_err
  else
    return false, "Invalid CSRF token"
  end
end

function _M.validate_token_filter(fn)
  return function(self, ...)
    local valid, err = validate_token(self)
    if not valid then
      ngx.log(ngx.WARN, "CSRF validation failure: ", err)

      ngx.status = 422
      ngx.header["Content-Type"] = "application/json; charset=utf-8"
      ngx.say(json_encode({
        ["error"] = t("Unprocessable Entity"),
      }))
      ngx.exit(ngx.HTTP_OK)

      return self:write({ layout = false })
    elseif fn then
      return fn(self, ...)
    end
  end
end

-- This can be used to replace the default "validate_token_filter" CSRF
-- protection in cases where the endpoint may be hit directly with the
-- "X-Admin-Auth-Token" header instead of a session cookie to authenticate the
-- admin. This is for server-side applications, where session cookies won't be
-- present, so cross-site scripting isn't an issue.
function _M.validate_token_or_admin_token_filter(fn)
  return function(self, ...)
    local skip_csrf = false
    local auth_token = ngx.var.http_x_admin_auth_token
    if auth_token and self.current_admin then
      local auth_token_hmac = hmac(auth_token)
      if auth_token_hmac == self.current_admin.authentication_token_hash then
        skip_csrf = true
      end
    end

    if not skip_csrf then
      return _M.validate_token_filter(fn)(self)
    elseif fn then
      return fn(self, ...)
    end
  end
end

return _M

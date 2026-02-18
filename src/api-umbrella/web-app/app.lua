local Admin = require "api-umbrella.web-app.models.admin"
local config = require("api-umbrella.utils.load_config")()
local csrf = require "api-umbrella.web-app.utils.csrf"
local db_init = require "api-umbrella.web-app.utils.db_init"
local error_messages_by_field = require "api-umbrella.web-app.utils.error_messages_by_field"
local escape_html = require("lapis.html").escape
local flash = require "api-umbrella.web-app.utils.flash"
local hmac = require "api-umbrella.utils.hmac"
local http_headers = require "api-umbrella.utils.http_headers"
local is_empty = require "api-umbrella.utils.is_empty"
local lapis = require "lapis"
local lapis_config = require("lapis.config").get()
local refresh_local_active_config_cache = require("api-umbrella.web-app.stores.active_config_store").refresh_local_cache
local resty_session = require "resty.session"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local table_keys = require("pl.tablex").keys

require "resty.session.ciphers.api_umbrella"
require "resty.session.hmac.api_umbrella"
require "resty.session.identifiers.api_umbrella"
require "resty.session.storage.api_umbrella_db"
require "resty.session.serializers.api_umbrella"

local supported_languages = table_keys(LOCALE_DATA)

-- Custom error handler so we only show the default lapis debug details in
-- development, and a generic error page in production.
local function handle_error(self, err, trace)
  ngx.log(ngx.ERR, "Unexpected error: " .. (err or "") .. "\n" .. (trace or ""))

  if lapis_config.show_errors then
    return lapis.Application.handle_error(self, err, trace)
  else
    self.res.headers["Content-Type"] = "text/html"
    return {
      status = 500,
      render = require("api-umbrella.web-app.views.500"),
      layout = false,
    }
  end
end

-- Override the default render_error_request so that backtraces aren't output
-- as an HTTP header in the test enivironment. This lets us verify that no
-- backtraces are output, even in the test environment (so we can have tests
-- around what will happen with error handling in production).
local function render_error_request(self, r, err, trace)
  r:write(self.handle_error(r, err, trace))
  return self:render_request(r)
end

local function handle_404(self)
  self.res.headers["Content-Type"] = "text/html"
  return self:write({
    status = 404,
    render = require("api-umbrella.web-app.views.404"),
    layout = false,
  })
end

local function current_admin_from_token()
  local current_admin
  local auth_token = ngx.var.http_x_admin_auth_token
  if auth_token then
    local auth_token_hmac = hmac(auth_token)
    local admin = Admin:find({ authentication_token_hash = auth_token_hmac })
    if admin and not admin:is_access_locked() then
      current_admin = admin
    end
  end

  return current_admin
end

-- Use the "session_db" instance for storing session data after the admin has
-- logged in. This session is backed by the database, so we have better
-- server-side control on expiring sessions, and it can't be spoofed even with
-- knowledge of the encryption secret key.
local session_db_options = {
  storage = "api_umbrella_db",
  cipher = "api_umbrella",
  hmac = "api_umbrella",
  serializer = "api_umbrella",
  identifier = "api_umbrella",
  name = "_api_umbrella_session",
  secret = assert(config["secret_key"]),
  random = {
    length = 40,
  },
  cookie = {
    samesite = "Lax",
    secure = true,
    httponly = true,
    idletime = 30 * 60, -- 30 minutes
    lifetime = 12 * 60 * 60, -- 12 hours
    renew = -1, -- Disable renew
  },
}
local function init_session_db(self)
  if not self.session_db then
    self.session_db = resty_session.new(session_db_options)
  end
end

-- Use the "session_cookie" instance for storing session data prior to the
-- admin logging in (for things like CSRF tokens on the login form and flash
-- notices on the login page). While still secure (the data is encrypted in the
-- cookie), we have less control over expiring this data and it can be
-- manipulated by someone with knowledge of the encryption secret key. But we
-- use this prior to login to simplify maintenance of the database-backed store
-- (so random, unauthenticated visits to the login page by bots don't generate
-- session records in the database for the CSRF token).
local session_cookie_options = {
  storage = "cookie",
  cipher = "api_umbrella",
  hmac = "api_umbrella",
  serializer = "api_umbrella",
  identifier = "api_umbrella",
  name = "_api_umbrella_session_client",
  secret = assert(config["secret_key"]),
  random = {
    length = 40,
  },
  cookie = {
    samesite = "Lax",
    secure = true,
    httponly = true,
    lifetime = 48 * 60 * 60, -- 48 hours
    renew = 1 * 60 * 60, -- 1 hour
  },
}
local function init_session_cookie(self)
  if not self.session_cookie then
    self.session_cookie = resty_session.new(self.session_cookie_options)
  end
end

local function current_admin_from_session(self)
  local current_admin
  self:init_session_db()
  local _, _, open_err = self.session_db:start()
  if open_err then
    if open_err == "session cookie idle time has passed" or open_err == "session cookie has expired" then
      flash.session(self, "info", t("Your session expired. Please sign in again to continue."))
    else
      ngx.log(ngx.ERR, "session open error: ", open_err)
    end
  end

  if self.session_db and self.session_db.data and self.session_db.data["admin_id"] then
    local admin_id = self.session_db.data["admin_id"]
    local admin = Admin:find({ id = admin_id })
    if admin and not admin:is_access_locked() then
      current_admin = admin
    end
  end

  return current_admin
end

local function before_filter(self)
  db_init()

  -- Refresh cache per request if background polling is disabled.
  if config["router"]["active_config"]["refresh_local_cache_interval"] == 0 then
    refresh_local_active_config_cache()
  end

  -- For the test environment setup a middleware that looks for the
  -- "test_delay_server_responses" cookie on requests, and if it's set, sleeps
  -- for that amount of time before returning responses.
  --
  -- This can be used for some Capybara integration tests that otherwise might
  -- happen too quickly (for example, checking that a loading spinner pops up
  -- while making an ajax request).
  if config["app_env"] == "test" then
    if ngx.var.cookie_test_delay_server_responses then
      ngx.sleep(tonumber(ngx.var.cookie_test_delay_server_responses))
    end
  end

  self.res.headers["Cache-Control"] = "no-cache, max-age=0, must-revalidate, no-store"
  self.res.headers["Pragma"] = "no-cache"

  ngx.ctx.locale = http_headers.preferred_accept_language(ngx.var.http_accept_language, supported_languages)
  self.t = function(_, message)
    return t(message)
  end

  self.field_errors = function(_, field)
    if not self.error_messages_by_field then
      self.error_messages_by_field = error_messages_by_field(self.errors)
    end

    if self.error_messages_by_field and not is_empty(self.error_messages_by_field[field]) then
      table.sort(self.error_messages_by_field[field])
      return '<span class="help-block">' .. escape_html(table.concat(self.error_messages_by_field[field], ", ")) .. "</span>"
    else
      return ""
    end
  end

  self.field_errors_class = function(_, field)
    if not self.error_messages_by_field then
      self.error_messages_by_field = error_messages_by_field(self.errors)
    end

    if self.error_messages_by_field and not is_empty(self.error_messages_by_field[field]) then
      return " has-error"
    else
      return ""
    end
  end

  self.generate_csrf_token = function()
    return csrf.generate_token(self)
  end

  self.session_db_options = session_db_options
  self.init_session_db = init_session_db
  self.session_cookie_options = session_cookie_options
  self.init_session_cookie = init_session_cookie
  flash.setup(self)
  local current_admin = current_admin_from_token()
  if not current_admin then
    current_admin = current_admin_from_session(self)
  end
  self.current_admin = current_admin
  ngx.ctx.current_admin = current_admin
end

local app = lapis.Application()
app:enable("etlua")
app.layout = require "api-umbrella.web-app.views.layout"
app.handle_error = handle_error
app.render_error_request = render_error_request
app.handle_404 = handle_404
app:before_filter(before_filter)

require("api-umbrella.web-app.actions.admin.auth_external")(app)
require("api-umbrella.web-app.actions.admin.passwords")(app)
require("api-umbrella.web-app.actions.admin.registrations")(app)
require("api-umbrella.web-app.actions.admin.server_side_loader")(app)
require("api-umbrella.web-app.actions.admin.sessions")(app)
require("api-umbrella.web-app.actions.admin.stats")(app)
require("api-umbrella.web-app.actions.admin.unlocks")(app)
require("api-umbrella.web-app.actions.api_users")(app)
require("api-umbrella.web-app.actions.v0.analytics")(app)
require("api-umbrella.web-app.actions.v1.admin_groups")(app)
require("api-umbrella.web-app.actions.v1.admin_permissions")(app)
require("api-umbrella.web-app.actions.v1.admins")(app)
require("api-umbrella.web-app.actions.v1.analytics")(app)
require("api-umbrella.web-app.actions.v1.api_scopes")(app)
require("api-umbrella.web-app.actions.v1.apis")(app)
require("api-umbrella.web-app.actions.v1.config")(app)
require("api-umbrella.web-app.actions.v1.contact")(app)
require("api-umbrella.web-app.actions.v1.user_roles")(app)
require("api-umbrella.web-app.actions.v1.users")(app)
require("api-umbrella.web-app.actions.v1.website_backends")(app)
require("api-umbrella.web-app.actions.web_app_health")(app)
require("api-umbrella.web-app.actions.web_app_state")(app)

if config["app_env"] == "test" then
  app:get("/api-umbrella/v1/test-500", function()
    error("Testing unexpected raised error")
  end)
end

return app

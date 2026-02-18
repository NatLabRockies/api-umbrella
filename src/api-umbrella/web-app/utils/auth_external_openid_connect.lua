local auth_external_path = require "api-umbrella.web-app.utils.auth_external_path"
local build_url = require "api-umbrella.utils.build_url"
local config = require("api-umbrella.utils.load_config")()
local deep_merge_overwrite_arrays = require "api-umbrella.utils.deep_merge_overwrite_arrays"
local deepcopy = require("pl.tablex").deepcopy
local json_decode = require("cjson").decode
local openidc = require "resty.openidc"
local random_token = require "api-umbrella.utils.random_token"

local DEBUG = ngx.DEBUG
if config["app_env"] == "development" or config["app_env"] == "test" then
  DEBUG = ngx.NOTICE
  openidc.set_logging(nil, { DEBUG = ngx.NOTICE })
end

local _M = {}

function _M.authenticate(self, strategy_name, callback)
  local callback_path = auth_external_path(strategy_name, "/callback")

  local openidc_options = deepcopy(config["web"]["admin"]["auth_strategies"][strategy_name])
  deep_merge_overwrite_arrays(openidc_options, {
    redirect_uri = build_url(callback_path),
    revoke_tokens_on_logout = true,
    logout_path = "/admin/logout",
    post_logout_redirect_uri = build_url("/admin/logout/callback"),
    session_contents = {
      id_token = true,

      enc_id_token = true,
      access_token = true,
      refresh_token = true,
    },
    lifecycle = {
      -- On successful authenticatication, short-circuit lua-resty-openidc's
      -- normal logic, and perform our own session finalization (to setup the
      -- API Umbrella session), and redirect to the appropriate place.
      on_authenticated = function(session)
        ngx.log(DEBUG, "OIDC Authorization Code Flow completed -> Performing API Umbrella callback")

        session:save()

        -- Call the provider-specific callback logic, which should handle
        -- authorizing the API Umbrella session and redirecting as appropriate.
        callback({
          id_token = session:get("id_token"),
          user = session:get("user"),
        })

        -- This shouldn't get hit, since callback should perform it's own
        -- redirect, but if this is unexpectedly hit, redirect back to the
        -- login page.
        return ngx.redirect(build_url("/admin/login"))
      end,
    },
  })

  if config["http_proxy"] or config["https_proxy"] then
    openidc_options["proxy_opts"] = {
      http_proxy = config["http_proxy"],
      https_proxy = config["https_proxy"],
    }
  end

  -- GitLab's OpenID Connect provider doesn't supply the email in the id_token
  -- (https://gitlab.com/gitlab-org/gitlab-ee/issues/5365). So for this
  -- provider, we must also access the userinfo endpoint to fetch the email.
  if strategy_name == "gitlab" then
    openidc_options["session_contents"]["user"] = true
  end

  -- When handling a logout, lua-resty-openidc doesn't currently append the
  -- optional "state" or "client_id" params to the logout URL, which Login.gov
  -- requires (at least "client_id", previously I believe "state"). So work
  -- around this by manually adding it.
  if ngx.var.uri == openidc_options["logout_path"] then
    -- Fetch the discovery information and see if the "end_session_endpoint"
    -- item is set.
    local discovery, err = openidc.get_discovery_doc(openidc_options)
    if err then
      ngx.log(ngx.ERR, "Failed to fetch openidc discovery: ", err)
    end
    if discovery and discovery["end_session_endpoint"] then
      -- Generate the state parameter to send.
      self:init_session_cookie()
      self.session_cookie:open()
      local oidc_state = random_token(64)
      self.session_cookie:set("openid_connect_state", oidc_state)
      self.session_cookie:save()

      -- Add the "state" param to the logout URL.
      local extra_logout_args = {
        state = oidc_state
      }

      -- Add the "client_id" param to the logout URL if id_token_hint won't be
      -- used.
      if openidc_options["redirect_after_logout_with_id_token_hint"] == false then
        extra_logout_args["client_id"] = openidc_options["client_id"]
      else
        openidc_options["redirect_after_logout_with_id_token_hint"] = true
      end

      -- Construct a new logout URL, appending any of our additional query
      -- params.
      local logout_uri = discovery["end_session_endpoint"]
      local separator = "?"
      if string.find(logout_uri, "?", 1, true) then
        separator = "&"
      end
      logout_uri = logout_uri .. separator .. ngx.encode_args(extra_logout_args)
      openidc_options["redirect_after_logout_uri"] = logout_uri
    elseif not discovery or not discovery["ping_end_session_endpoint"] then
      -- lua-resty-openidc's default behavior is to render plain HTML response
      -- to the logout endpoint. So if we're not performing a RP-initiaited
      -- logout sequence, then make sure we redirect back to the final
      -- destination, rather than rendering the HTML page.
      openidc_options["redirect_after_logout_uri"] = openidc_options["post_logout_redirect_uri"]
    end
  end

  -- Create a separate session for lua-resty-openidc's storage so it doesn't
  -- conflict with any of our sessions.
  local session_options = deepcopy(self.session_db_options)
  session_options["cookie_name"] = "_api_umbrella_openidc"

  -- In the test environment allow mocking the login process.
  if config["app_env"] == "test" and ngx.var.cookie_test_mock_userinfo then
    if ngx.var.uri == callback_path then
      local mock_userinfo = require "api-umbrella.web-app.utils.test_env_mock_userinfo"
      local res = json_decode(mock_userinfo())
      local err = nil
      callback(res, err)
      return res, err
    elseif ngx.var.uri == openidc_options["logout_path"] then
      return ngx.redirect(openidc_options["post_logout_redirect_uri"])
    else
      return ngx.redirect(openidc_options["redirect_uri"])
    end
  end

  local res, err = openidc.authenticate(openidc_options, nil, nil, session_options)
  if err then
    ngx.log(ngx.WARN, "OpenID Connect error: ", err)
  end

  -- Successful authentications should be handled in the /callback request by
  -- the "on_authenticated" hook. However, in the even of errors,
  -- "openidc.authenticate" can return an error, which can be handled here by
  -- the same callback.
  if ngx.var.uri == callback_path then
    callback(res, err)
  end

  return res, err
end

return _M

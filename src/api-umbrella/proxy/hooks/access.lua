-- Try to find the matching API backend first, since it dictates further
-- settings and requirements.
local ngx_ctx = ngx.ctx
local api = ngx_ctx.matched_api
if not api then
  return true
end

local api_key_validator = require "api-umbrella.proxy.middleware.api_key_validator"
local api_settings = require "api-umbrella.proxy.middleware.api_settings"
local error_handler = require "api-umbrella.proxy.error_handler"
local https_transition_user_validator = require "api-umbrella.proxy.middleware.https_transition_user_validator"
local https_validator = require "api-umbrella.proxy.middleware.https_validator"
local ip_validator = require "api-umbrella.proxy.middleware.ip_validator"
local rate_limit = require "api-umbrella.proxy.middleware.rate_limit"
local referer_validator = require "api-umbrella.proxy.middleware.referer_validator"
local resolve_api_key = require "api-umbrella.proxy.middleware.resolve_api_key"
local rewrite_request = require "api-umbrella.proxy.middleware.rewrite_request"
local role_validator = require "api-umbrella.proxy.middleware.role_validator"
local scheduled_brownout = require "api-umbrella.proxy.middleware.scheduled_brownout"
local user_settings = require "api-umbrella.proxy.middleware.user_settings"

local err
local err_data
local user
local settings

-- Fetch the settings from the matched API.
settings, err = api_settings(ngx_ctx, api)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- Find the API key set on the request.
err = resolve_api_key(ngx_ctx)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- If this API requires access over HTTPS, verify that it's happening.
--
-- Do this before verifying the API key so the ordering of the error messages
-- encourage better security (tell the user first to make the request over
-- HTTPS, rather than first telling them to supply their API key on an insecure
-- HTTP request).
err, err_data = https_validator(ngx_ctx, settings)
if err then
  return error_handler(ngx_ctx, err, settings, err_data)
end

-- Validate the API key that's passed in, if this API requires API keys.
user, err = api_key_validator(ngx_ctx, settings)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- Check for any active brownouts for this specific API and the current time.
--
-- This occurs after the api_key_validator, so that the user information is
-- fetched and logged for keys hitting this error.
err, err_data = scheduled_brownout(ngx_ctx, api)
if err then
  return error_handler(ngx_ctx, err, settings, err_data)
end

-- Fetch and merge any user-specific settings.
err = user_settings(settings, user)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- Store the settings for use by the header_filter.
ngx_ctx.settings = settings

-- For API backends that are transitioning to HTTPS usage, verify these after
-- the API key information has been fetched (since the transition behavior
-- depends on the specific API key's create date).
err, err_data = https_transition_user_validator(ngx_ctx, settings, user)
if err then
  return error_handler(ngx_ctx, err, settings, err_data)
end

-- If this API requires roles, verify that the user has those.
err = role_validator(settings, user)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- If this API or user requires the traffic come from certain IP addresses,
-- verify those.
err = ip_validator(ngx_ctx, settings)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- If this API or user requires the traffic come from certain HTTP referers,
-- verify those.
err = referer_validator(settings)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- If we've gotten this far, it means the user is authorized to access this
-- API, so apply the rate limits for this user and API.
err = rate_limit(api, settings, user, ngx_ctx.remote_addr)
if err then
  return error_handler(ngx_ctx, err, settings)
end

-- Perform any request rewriting.
err = rewrite_request(ngx_ctx, user, api, settings)
if err then
  return error_handler(ngx_ctx, err, settings)
end

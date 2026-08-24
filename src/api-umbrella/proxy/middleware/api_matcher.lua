local append_array = require "api-umbrella.utils.append_array"
local config = require("api-umbrella.utils.load_config")()
local matches_hostname = require "api-umbrella.utils.matches_hostname"
local stringx = require "pl.stringx"
local utils = require "api-umbrella.proxy.utils"

local re_match = ngx.re.match
local re_sub = ngx.re.sub
local set_uri = utils.set_uri
local startswith = stringx.startswith

local function apis_for_request_host(ngx_ctx, active_config)
  local apis = {}

  local all_apis = active_config["api_backends"] or {}
  local apis_for_default_host = {}
  local host_normalized = ngx_ctx.host_normalized
  for _, api in ipairs(all_apis) do
    if matches_hostname(host_normalized, api["_frontend_host_normalized"], api["_frontend_host_wildcard_regex"]) then
      table.insert(apis, api)
    elseif api["_frontend_host_normalized"] == config["_default_hostname_normalized"] then
      table.insert(apis_for_default_host, api)
    end
  end

  -- If a default host exists, append its APIs to the end so they have a lower
  -- matching precedence than any APIs that actually match the host.
  append_array(apis, apis_for_default_host)

  return apis
end

local function match_api(ngx_ctx, active_config, request_path)
  -- Find the API backends that match this host.
  local apis = apis_for_request_host(ngx_ctx, active_config)

  -- Search through each API backend for URL path prefix matches. Choose the
  -- match that is the longest prefix path string, since this would be the most
  -- specific match in cases where multiple path prefixes would match.
  local matched_api = nil
  local matched_url_match = nil
  local matched_length = 0
  for _, api in ipairs(apis) do
    if api["url_matches"] then
      for _, url_match in ipairs(api["url_matches"]) do
        local matches = false
        if not url_match["exact_match"] and startswith(request_path, url_match["frontend_prefix"]) then
          matches = true
        elseif url_match["exact_match"] and request_path == url_match["frontend_prefix"] then
          matches = true
        end

        local length = string.len(url_match["frontend_prefix"])
        if matches and length > matched_length then
          matched_api = api
          matched_url_match = url_match
          matched_length = length
        end
      end
    end
  end

  if matched_api and matched_url_match then
    return matched_api, matched_url_match
  end
end

return function(ngx_ctx, active_config)
  local request_path = ngx_ctx.original_uri_path
  local api, url_match = match_api(ngx_ctx, active_config, request_path)

  if api and url_match then
    -- Rewrite the URL prefix path.
    local new_path, _, new_path_err = re_sub(request_path, url_match["_frontend_prefix_regex"], url_match["backend_prefix"], "jo")
    if new_path_err then
      ngx.log(ngx.ERR, "regex error: ", new_path_err)
    elseif new_path ~= request_path then
      set_uri(ngx_ctx, new_path)
    end

    local host = api["backend_host"] or ngx_ctx.host
    if api["_frontend_host_wildcard_regex"] then
      local matches, match_err = re_match(ngx_ctx.host_normalized, api["_frontend_host_wildcard_regex"], "jo")
      if matches then
        local wildcard_portion = matches[1]
        if wildcard_portion then
          local _, sub_err
          host, _, sub_err = re_sub(host, "^([*.])", wildcard_portion, "jo")
          if sub_err then
            ngx.log(ngx.ERR, "regex error: ", sub_err)
          end
        end
      elseif match_err then
        ngx.log(ngx.ERR, "regex error: ", match_err)
      end
    end

    ngx_ctx.backend_host = host

    return api, url_match
  else
    return nil, nil, "not_found"
  end
end

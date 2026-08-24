local append_array = require "api-umbrella.utils.append_array"
local escape_regex = require "api-umbrella.utils.escape_regex"
local host_normalize = require "api-umbrella.utils.host_normalize"
local matches_hostname = require "api-umbrella.utils.matches_hostname"
local mustache_unescape = require "api-umbrella.utils.mustache_unescape"
local set_hostname_regex = require "api-umbrella.utils.active_config_store.set_hostname_regex"
local split = require("pl.utils").split
local startswith = require("pl.stringx").startswith
local table_size = require("pl.tablex").size

local decode_args = ngx.decode_args
local re_gsub = ngx.re.gsub

local function cache_scheduled_brownouts(config, api)
  local hosts = config["hosts"]
  if hosts then
    local frontend_host_normalized = api["_frontend_host_normalized"]
    for _, host in ipairs(hosts) do
      local scheduled_brownouts = host["scheduled_brownouts"]
      if scheduled_brownouts and (frontend_host_normalized == host["_hostname_normalized"] or matches_hostname(frontend_host_normalized, host["_hostname_normalized"], host["_hostname_wildcard_regex"])) then
        if api["_scheduled_brownouts"] == nil then
          api["_scheduled_brownouts"] = {}
        end

        append_array(api["_scheduled_brownouts"], scheduled_brownouts)
      end
    end
  end
end

return function(config, api)
  if not api then return end

  if api["frontend_host"] then
    set_hostname_regex(api, "frontend_host")
  end

  if api["backend_host"] == "" then
    api["backend_host"] = nil
  end

  if api["backend_host"] then
    api["_backend_host_normalized"] = host_normalize(api["backend_host"])
  end

  if api["servers"] then
    for index, server in ipairs(api["servers"]) do
      if not server["id"] then
        server["id"] = api["id"] .. "-" .. index
      end
    end
  end

  if api["url_matches"] then
    for _, url_match in ipairs(api["url_matches"]) do
      url_match["_frontend_prefix_regex"] = "^" .. escape_regex(url_match["frontend_prefix"])
      url_match["_backend_prefix_regex"] = "^" .. escape_regex(url_match["backend_prefix"])

      url_match["_frontend_prefix_contains_backend_prefix"] = false
      if startswith(url_match["frontend_prefix"], url_match["backend_prefix"]) then
        url_match["_frontend_prefix_contains_backend_prefix"] = true
      end

      url_match["_backend_prefix_contains_frontend_prefix"] = false
      if startswith(url_match["backend_prefix"], url_match["frontend_prefix"]) then
        url_match["_backend_prefix_contains_frontend_prefix"] = true
      end
    end
  end

  if api["rewrites"] then
    for _, rewrite in ipairs(api["rewrites"]) do
      rewrite["http_method"] = string.lower(rewrite["http_method"])

      -- Route pattern matching implementation based on
      -- https://github.com/bjoerge/route-pattern
      -- TODO: Cleanup!
      if rewrite["matcher_type"] == "route" and rewrite["frontend_matcher"] and rewrite["backend_replacement"] then
        local backend_replacement = mustache_unescape(rewrite["backend_replacement"])
        local backend_parts = split(backend_replacement, "?", true, 2)
        rewrite["_backend_replacement_path"] = backend_parts[1]
        rewrite["_backend_replacement_args"] = backend_parts[2]

        local frontend_parts = split(rewrite["frontend_matcher"], "?", true, 2)
        local path = frontend_parts[1]
        local args = frontend_parts[2]

        local escapeRegExp = "[\\-{}\\[\\]+?.,\\\\^$|#\\s]"
        local namedParam = [[:(\w+)]]
        local splatNamedParam = [[\*(\w+)]]
        local subPath = [[\*([^\w]|$)]]

        local frontend_path_regex, _, gsub_err = re_gsub(path, escapeRegExp, "\\$0")
        if gsub_err then
          ngx.log(ngx.ERR, "regex error: ", gsub_err)
        end

        frontend_path_regex, _, gsub_err = re_gsub(frontend_path_regex, subPath, [[.*?$1]])
        if gsub_err then
          ngx.log(ngx.ERR, "regex error: ", gsub_err)
        end

        frontend_path_regex, _, gsub_err = re_gsub(frontend_path_regex, namedParam, [[(?<$1>[^/]+)]])
        if gsub_err then
          ngx.log(ngx.ERR, "regex error: ", gsub_err)
        end

        frontend_path_regex, _, gsub_err = re_gsub(frontend_path_regex, splatNamedParam, [[(?<$1>.*?)]])
        if gsub_err then
          ngx.log(ngx.ERR, "regex error: ", gsub_err)
        end

        frontend_path_regex, _, gsub_err = re_gsub(frontend_path_regex, "/$", "")
        if gsub_err then
          ngx.log(ngx.ERR, "regex error: ", gsub_err)
        end

        rewrite["_frontend_path_regex"] = "^" .. frontend_path_regex .. "/?$"

        if args then
          args = decode_args(args)
          rewrite["_frontend_args_length"] = table_size(args)
          rewrite["_frontend_args"] = {}
          for key, value in pairs(args) do
            if key == "*" and value == true then
              rewrite["_frontend_args_allow_wildcards"] = true
            else
              rewrite["_frontend_args"][key] = {}
              if type(value) == "string" and string.sub(value, 1, 1) == ":" then
                rewrite["_frontend_args"][key]["named_capture"] = string.sub(value, 2, -1)
              else
                rewrite["_frontend_args"][key]["must_equal"] = value
              end
            end
          end
        end
      end
    end
  end

  cache_scheduled_brownouts(config, api)
end

local config = require("api-umbrella.utils.load_config")()
local host_normalize = require "api-umbrella.utils.host_normalize"

local ngx_var = ngx.var
local re_match = ngx.re.match
local re_sub = ngx.re.sub

return function(path)
  local host = config["web"]["default_host"] or ngx_var.server_name
  local proto = config["web"]["default_scheme"] or ngx_var.scheme

  -- Since we're no longer using X-Forwarded-Host for the host header, account
  -- for the "override" port settings that would have been normally set by
  -- `hooks/rewrite.lua`.
  --
  -- I think we should maybe revisit whether any of this override port stuff is
  -- actually needed, though, since I don't believe we're really utilizing it
  -- any longer.
  local forwarded_proto = ngx_var.http_x_forwarded_proto
  if forwarded_proto == "http" and config["override_public_http_port"] then
    host = re_sub(host, "(:.*$|$)", ":" .. config["override_public_http_port"], "jo")
  elseif forwarded_proto == "https" and config["override_public_https_port"] then
    host = re_sub(host, "(:.*$|$)", ":" .. config["override_public_https_port"], "jo")
  end

  local port
  local matches, match_err = re_match(host, [[:(\d+)$]], "jo")
  if matches then
    port = tonumber(matches[1])
  else
    if match_err then
      ngx.log(ngx.ERR, "regex error: ", match_err)
    end

    if proto == "http" then
      port = config["http_port"]
    else
      port = config["https_port"]
    end

    if not port then
      port = tonumber(ngx_var.server_port)
    end
  end

  local url = proto .. "://" .. host_normalize(host)
  if (proto == "https" and port ~= 443) or (proto == "http" and port ~= 80)then
    url = url .. ":" .. port
  end
  url = url .. path

  return url
end

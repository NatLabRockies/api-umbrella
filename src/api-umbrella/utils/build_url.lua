local config = require("api-umbrella.utils.load_config")()
local host_normalize = require "api-umbrella.utils.host_normalize"

local ngx_var = ngx.var
local re_match = ngx.re.match

return function(path)
  local host = config["web"]["default_host"] or ngx_var.server_name
  local proto = config["web"]["default_scheme"] or ngx_var.scheme

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

local config = require("api-umbrella.utils.load_config")()
local http = require "resty.http"
local interval_lock = require "api-umbrella.utils.interval_lock"
local json_decode = require("cjson").decode
local json_encode = require "api-umbrella.utils.json_encode"

local delay = 5 -- in seconds
local checks = {
  {
    name = "nginx",
    url = "http://127.0.0.1:" .. config["api_server"]["port"] .. "/_nginx-status",
  },
  {
    name = "trafficserver",
    url = "http://127.0.0.1:" .. config["trafficserver"]["port"] .. "/_trafficserver-stats",
    http_options = {
      headers = {
        ["Host"] = "api-umbrella-trafficserver-health.internal",
      },
    }
  },
}

local _M = {}

local function do_run()
  local httpc = http.new()
  httpc:set_timeout(5000)

  for _, check in ipairs(checks) do
    local res, err = httpc:request_uri(check.url, check.http_options)
    if err then
      ngx.log(ngx.ERR, "health stats failure - failed to fetch " .. check.name .. " health: ", err)
    elseif res.status == 200 and (res.headers["Content-Type"] == "application/json" or res.headers["Content-Type"] == "text/json") then
      local data = json_decode(res.body)
      ngx.log(ngx.NOTICE, "health stats - " .. check.name .. " health: ", json_encode(data))
    elseif res.headers["Content-Type"] ~= "application/json" then
      ngx.log(ngx.ERR, "health stats failure - response for " .. check.name .. " health not JSON: ", res.body)
    else
      ngx.log(ngx.ERR, "health stats failure - unncessful response for " .. check.name .. " health: ", res.body)
    end
  end
end

function _M.spawn()
  interval_lock.repeat_with_mutex('health_stats', delay, do_run)
end

return _M

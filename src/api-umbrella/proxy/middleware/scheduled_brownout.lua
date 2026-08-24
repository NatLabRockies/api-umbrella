local config = require("api-umbrella.utils.load_config")()

local ngx_var = ngx.var
local now = ngx.now
local re_find = ngx.re.find

return function(ngx_ctx, api)
  local scheduled_brownouts = api["_scheduled_brownouts"]
  if scheduled_brownouts then
    local current_time = now()
    if config["app_env"] == "test" then
      local fake_time = ngx_var.http_x_fake_time
      if fake_time then
        current_time = tonumber(fake_time)
      end
    end

    local original_uri_path = ngx_ctx.original_uri_path
    for _, scheduled_brownout in ipairs(scheduled_brownouts) do
      for _, schedule in ipairs(scheduled_brownout["schedule"]) do
        if current_time >= schedule["_start_time_timestamp"] and current_time < schedule["_end_time_timestamp"] then
          local find_from, _, find_err = re_find(original_uri_path, scheduled_brownout["path_regex"], "jo")
          if find_from then
            return "scheduled_brownout", {
              status_code = scheduled_brownout["status_code"],
              message = scheduled_brownout["message"],
              cache_control = "no-store",
            }
          elseif find_err then
            ngx.log(ngx.ERR, "regex error: ", find_err)
          end
        end
      end
    end
  end

  return nil
end

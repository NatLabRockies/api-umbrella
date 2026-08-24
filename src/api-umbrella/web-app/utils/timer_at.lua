local db_init = require "api-umbrella.web-app.utils.db_init"
local timer_at = require("lapis.nginx").timer_at

-- For Lapis web app requests instead of using `ngx.timer.at`, use this wrapper which accomplishes 2 things:
--
-- 1. Uses Lapis' existing wrapper to ensure db disconnect or other after tasks
--    occur:
--    https://github.com/leafo/lapis/blob/v1.17.0/lapis/nginx.moon#L166-L177
-- 2. Integrate our own `db_init` handler to ensure database connections inside
--    the timer have the proper search_path and other settings configured.
return function(delay, callback, ...)
  timer_at(delay, function(_premature, ...)
    db_init()
    return callback(...)
  end, ...)
end

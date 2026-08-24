local db = require "lapis.db"
local pg_utils = require "api-umbrella.utils.pg_utils"

-- Set session variables for the database connection that Lapis uses (always
-- use UTC and set an app name for auditing). This needs to be called before
-- Lapis `db.query` is called (by either Lapis requests, or also before Lapis
-- timers).
return function()
  local pg = db.connect()

  -- I don't think this should really be possible, but if somehow lapis has
  -- already established a connection, then `db.connect()` will return `nil`.
  -- So in that case, fetch the cached connection Lapis uses internally, and
  -- force the full setup (even if it's a reused socket), since we don't know
  -- if this socket was fully setup by Lapis or not.
  local force_first_time_setup = true
  if not pg then
    pg = ngx.ctx.pgmoon_default
    force_first_time_setup = true
  end

  pg_utils.setup_connection(pg, "api-umbrella-web-app", force_first_time_setup)
end

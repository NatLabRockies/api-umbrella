local config = require("api-umbrella.utils.load_config")()
local int64 = require "api-umbrella.utils.int64"
local pgmoon = require "pgmoon"
local random_token = require "api-umbrella.utils.random_token"
local xpcall_error_handler = require "api-umbrella.utils.xpcall_error_handler"

-- Preload modules that pgmoon may require at query() time.
require "pgmoon.arrays"
require "pgmoon.json"
require "resty.openssl"
require "resty.openssl.auxiliary.nginx"
require "resty.openssl.auxiliary.nginx_c"

local _encode_bytea = pgmoon.Postgres.encode_bytea
local _escape_identifier = pgmoon.Postgres.escape_identifier
local _escape_literal = pgmoon.Postgres.escape_literal
local now = ngx.now
local pg_null = pgmoon.Postgres.NULL
local re_gsub = ngx.re.gsub
local sleep = ngx.sleep

local _M = {}

_M.db_config = {
  host = config["postgresql"]["host"],
  port = config["postgresql"]["port"],
  database = config["postgresql"]["database"],
  user = config["postgresql"]["username"],
  password = config["postgresql"]["password"],
  ssl = config["postgresql"]["ssl"],
  ssl_verify = config["postgresql"]["ssl_verify"],
  ssl_required = config["postgresql"]["ssl_required"],
}

local BYTEA_METATABLE = {}
local IDENTIFIER_METATABLE = {}
local LIST_METATABLE = {}
local RAW_METATABLE = {}

local function encode_values(values)
  local escaped_columns = {}
  local escaped_values = {}
  for column, value in pairs(values) do
    table.insert(escaped_columns, _M.escape_identifier(column))
    table.insert(escaped_values, _M.escape_literal(value))
  end

  return "(" .. table.concat(escaped_columns, ", ") .. ") VALUES (" .. table.concat(escaped_values, ", ") .. ")"
end

local function encode_assigns(values)
  local escaped_assigns = {}
  for column, value in pairs(values) do
    table.insert(escaped_assigns, _M.escape_identifier(column) .. " = " .. _M.escape_literal(value))
  end

  return table.concat(escaped_assigns, ", ")
end

local function encode_where(values)
  local escaped_assigns = {}
  for column, value in pairs(values) do
    table.insert(escaped_assigns, _M.escape_identifier(column) .. " = " .. _M.escape_literal(value))
  end

  return table.concat(escaped_assigns, " AND ")
end

function _M.bytea(value)
  return setmetatable({ value }, BYTEA_METATABLE)
end

function _M.is_bytea(value)
  return getmetatable(value) == BYTEA_METATABLE
end

function _M.identifier(value)
  return setmetatable({ value }, IDENTIFIER_METATABLE)
end

function _M.is_identifier(value)
  return getmetatable(value) == IDENTIFIER_METATABLE
end

function _M.list(value)
  return setmetatable({ value }, LIST_METATABLE)
end

function _M.is_list(value)
  return getmetatable(value) == LIST_METATABLE
end

function _M.raw(value)
  return setmetatable({ value }, RAW_METATABLE)
end

function _M.is_raw(value)
  return getmetatable(value) == RAW_METATABLE
end

function _M.escape_like(value)
  return re_gsub(value, "[\\\\%_]", "\\$0", "jo")
end

function _M.escape_literal(value)
  if value == nil or value == pg_null then
    return "NULL"
  elseif _M.is_list(value) then
    local escaped = {}
    for _, val in ipairs(value[1]) do
      table.insert(escaped, _escape_literal(nil, val))
    end
    return "(" .. table.concat(escaped, ", ") .. ")"
  elseif _M.is_raw(value) then
    return tostring(value[1])
  elseif int64.is_64bit(value) then
    return _escape_literal(nil, int64.to_string(value))
  elseif _M.is_bytea(value) then
    return _encode_bytea(nil, value[1])
  elseif _M.is_identifier(value) then
    return _escape_identifier(nil, value[1])
  else
    return _escape_literal(nil, value)
  end
end

function _M.escape_identifier(value)
  return _escape_identifier(nil, value)
end

function _M.setup_type_casting(pg)
  -- By default, pgmoon treats bigint values as normal lua numbers, which can
  -- lose precision: https://github.com/leafo/pgmoon/issues/48
  --
  -- To solve this, we'll cast PostgreSQL bigint values into a LuaJIT's FFI 64
  -- bit integers (int64_t), since we're only targeting LuaJIT.
  pg:set_type_deserializer(20, "bigint_int64", function(_, value)
    return int64.from_string(value)
  end)

  -- pgmoon is currently missing support for handling PostgreSQL inet array
  -- types, so it doesn't know how to decode/encode these. So manually add
  -- inet[]'s oid (1041) so that they're handled as an array of strings.
  pg:set_type_deserializer(1041, "array_string")
end

function _M.setup_socket_timeouts(pg)
  -- We'll assume statement_timeout should take precedence, so set a much
  -- longer socket timeout to work with any customized statement timeout.
  local send_read_timeout = 10 * 60 * 1000 -- 10 minutes

  pg.sock:settimeouts(config["postgresql"]["connect_timeout"], send_read_timeout, send_read_timeout)
end

function _M.setup_session_vars(pg, application_name)
  local queries = {
    "SET search_path = api_umbrella, public",

    -- Set an application name for connection details.
    "SET SESSION audit.application_name = " .. _M.escape_literal(application_name),

    -- Always use UTC.
    "SET SESSION timezone = 'UTC'",

    -- Define statement timeout to prevent accidental long-running queries.
    -- "SET SESSION statement_timeout = " .. _M.escape_literal(config["postgresql"]["statement_timeout"] .. "ms"),
  }
  _M.query(table.concat(queries, "; "), nil, {
    pg = pg,
    -- Skip keepalive, since this is called during `connect` itself, so we
    -- don't want setup keepalive until the real query has been performed.
    skip_keepalive = true,
  })
end

function _M.setup_connection(pg, application_name, force_first_time_setup)
  _M.setup_type_casting(pg)

  -- The first time this socket is used (but not when reusing keepalive
  -- sockets), setup any session variables on the connection.
  if pg.sock:getreusedtimes() == 0 or force_first_time_setup then
    _M.setup_socket_timeouts(pg)
    _M.setup_session_vars(pg, application_name)
  end
end

function _M.connect()
  -- Try connecting a few times in case PostgreSQL is being restarted or
  -- starting up.
  --
  -- Note that pgmoon.new also needs to be inside the retry-loop, otherwise
  -- "the database system is starting up" errors from postgresql can lead to a
  -- nil socket inside pgmoon's internals on the next retry.
  local pg, ok, err
  for _ = 1, 5 do
    pg = pgmoon.new(_M.db_config)
    ok, err = pg:connect()
    if not ok then
      ngx.log(ngx.ERR, "failed to connect to database: ", err)
      sleep(0.1)
    else
      break
    end
  end

  if not ok then
    return nil, err
  end

  _M.setup_connection(pg, "api-umbrella")

  return pg
end

function _M.query(query, values, options)
  local pg
  if options and options["pg"] then
    pg = options["pg"]
  else
    pg = _M.connect()
  end
  if not pg then
    return nil, "connection error"
  end

  -- Allow custom timeouts to be specified for individual queries.
  -- if options and options["statement_timeout"] then
  --   local timeout_result, timeout_err = pg:query("SET SESSION statement_timeout = " .. _M.escape_literal(options["statement_timeout"] .. "ms"))
  --   if not timeout_result then
  --     ngx.log(ngx.ERR, "postgresql query error: ", timeout_err)
  --   end
  -- end

  if values then
    local escaped_values = {}
    for key, value in pairs(values) do
      escaped_values[key] = _M.escape_literal(value)
    end

    -- Find all bind variable syntax (":word") and replace with the appropriate
    -- variable. Be careful not to match "::word", so that we don't match
    -- postgres type casting (eg, "foo::date").
    local _, gsub_err
    query, _, gsub_err = re_gsub(query, [[(?<!:):(\w+)]], function(match)
      local key = match[1]
      local escaped_value = escaped_values[key] or "NULL"
      return escaped_value
    end)
    if gsub_err then
      ngx.log(ngx.ERR, "regex error: ", gsub_err)
    end
  end

  local app_env = config["app_env"]
  if app_env == "development" or app_env == "test" or (options and options["verbose"]) then
    local level = ngx.NOTICE
    if options and options["quiet"] then
      level = ngx.DEBUG
    end
    ngx.log(level, query)
    if options and options["verbose"] then
      print(query)
    end
  end
  local result, num_queries = pg:query(query)
  local err
  if not result then
    err = num_queries
    ngx.log(ngx.ERR, "postgresql query error: ", err)
  end

  -- If custom timeouts were specified, revert back to default timeouts.
  -- if options and options["statement_timeout"] then
  --   local timeout_result, timeout_err = pg:query("SET SESSION statement_timeout = " .. _M.escape_literal(config["postgresql"]["statement_timeout"] .. "ms"))
  --   if not timeout_result then
  --     ngx.log(ngx.ERR, "postgresql query error: ", timeout_err)
  --   end
  -- end

  if not options or not options["skip_keepalive"] then
    local keepalive_ok, keepalive_err = pg:keepalive()
    if not keepalive_ok then
      ngx.log(ngx.ERR, "postgresql keepalive error: ", keepalive_err)
    end
  end

  if options and options["fatal"] and err then
    error(err)
  end

  return result, err
end

function _M.insert(table_name, values, options)
  local query = "INSERT INTO " .. _M.escape_identifier(table_name) .. " " .. encode_values(values)
  return _M.query(query, nil, options)
end

function _M.update(table_name, where, values, options)
  local query = "UPDATE " .. _M.escape_identifier(table_name) .. " SET " .. encode_assigns(values) .. " WHERE " .. encode_where(where)
  return _M.query(query, nil, options)
end

function _M.delete(table_name, where, options)
  local query = "DELETE FROM " .. _M.escape_identifier(table_name) .. " WHERE " .. encode_where(where)
  return _M.query(query, nil, options)
end

function _M.transaction(options, callback)
  if not options then
    options = {}
  end

  -- Use the same pg instance for all queries inside of the transaction,
  -- otherwise the transaction may fail if queries switch between different
  -- connections in the connection pool.
  options["pg"] = _M.connect()
  if not options["pg"] then
    return nil, "connection error"
  end

  -- Since we're using the same connection, we want to defer releasing the
  -- connection for keepalive (back into the pool) until the transaction is
  -- committed.
  options["skip_keepalive"] = true

  local _, query_err = _M.query("BEGIN", nil, options)
  if query_err then
    return false, query_err
  end

  local err
  local pcall_ok, result = xpcall(callback, xpcall_error_handler)
  if not pcall_ok then
    err = result
  end

  options["skip_keepalive"] = false
  _, query_err = _M.query("COMMIT", nil, options)
  if query_err then
    if err then
      return false, err .. ", " .. query_err
    else
      return false, query_err
    end
  end

  return pcall_ok, err
end

function _M.cursor(query, values, cursor_size, options, callback)
  if not options then
    options = {}
  end

  local cursor_name = "cursor_" .. (now() * 1000) .. "_" .. string.lower(random_token(16))
  local declare_sql = "DECLARE " .. cursor_name .. " NO SCROLL CURSOR WITHOUT HOLD FOR " .. query
  local fetch_sql = "FETCH " .. tonumber(cursor_size) .. " FROM " .. cursor_name

  return _M.transaction(options, function()
    local _, query_err = _M.query(declare_sql, values, options)
    if query_err then
      return false, query_err
    end

    local results
    repeat
      local results_err
      results, results_err = _M.query(fetch_sql, nil, options)

      if results_err then
        return false, results_err
      end

      if results and #results > 0 then
        callback(results)
      end
    until not results or #results == 0

    return true
  end)
end

return _M

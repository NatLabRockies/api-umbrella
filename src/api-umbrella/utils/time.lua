local icu_date = require "icu-date-ffi"
local json_null = require("cjson").null
local xpcall_error_handler = require "api-umbrella.utils.xpcall_error_handler"

local null = ngx.null

local date = icu_date.new()
local format_iso8601 = icu_date.formats.pattern("yyyy-MM-dd'T'HH:mm:ssZZZZZ")
local format_iso8601_ms = icu_date.formats.pattern("yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ")
local format_postgres = icu_date.formats.pattern("yyyy-MM-dd HH:mm:ss.SSSSxxx")
local format_postgres_no_millis = icu_date.formats.pattern("yyyy-MM-dd HH:mm:ssxxx")

local _M = {}

local function parse_postgres(string)
  local ok, err
  ok = pcall(date.parse, date, format_postgres, string)
  if not ok then
    ok, err = xpcall(date.parse, xpcall_error_handler, date, format_postgres_no_millis, string)
    if not ok then
      ngx.log(ngx.ERR, "Failed to parse postgres time (" .. (tostring(string) or "") .. "): " .. (tostring(err) or ""))
      return false
    end
  end

  -- Since the postgres format may include a custom time zone, be sure to
  -- normalize all parsed times to UTC.
  date:set_time_zone_id("UTC")
end

function _M.timestamp_to_iso8601(timestamp)
  if not timestamp or timestamp == null or timestamp == json_null then
    return nil
  end

  date:set_millis(timestamp * 1000)
  return date:format(format_iso8601)
end

function _M.timestamp_ms_to_iso8601(timestamp)
  if not timestamp or timestamp == null or timestamp == json_null then
    return nil
  end

  date:set_millis(timestamp)
  return date:format(format_iso8601)
end

function _M.postgres_to_timestamp(string)
  if not string or string == null or string == json_null then
    return nil
  end

  parse_postgres(string)
  return date:get_millis() / 1000
end

function _M.postgres_to_iso8601(string)
  if not string or string == null or string == json_null then
    return nil
  end

  parse_postgres(string)
  return date:format(format_iso8601)
end

function _M.postgres_to_iso8601_ms(string)
  if not string or string == null or string == json_null then
    return nil
  end

  parse_postgres(string)
  return date:format(format_iso8601_ms)
end

function _M.timestamp_ms_to_csv(timestamp)
  if not timestamp or timestamp == null or timestamp == json_null then
    return nil
  end

  date:set_millis(timestamp)
  return date:format(format_iso8601_ms)
end

function _M.iso8601_to_timestamp(string)
  if not string or string == null or string == json_null then
    return nil
  end

  date:parse(format_iso8601, string)
  return date:get_millis() / 1000
end

function _M.iso8601_ms_to_timestamp(string)
  if not string or string == null or string == json_null then
    return nil
  end

  date:parse(format_iso8601_ms, string)
  return date:get_millis() / 1000
end

function _M.iso8601_to_timestamp_ms(string)
  if not string or string == null or string == json_null then
    return nil
  end

  date:parse(format_iso8601, string)
  return date:get_millis()
end

function _M.iso8601_to_csv(string)
  if not string or string == null or string == json_null then
    return nil
  end

  date:parse(format_iso8601, string)
  return date:format(format_iso8601)
end

function _M.iso8601_ms_to_csv(string)
  if not string or string == null or string == json_null then
    return nil
  end

  date:parse(format_iso8601_ms, string)
  return date:format(format_iso8601_ms)
end

function _M.opensearch_to_csv(value)
  if not value then
    return nil
  end

  if type(value) == "string" then
    return _M.iso8601_ms_to_csv(value)
  else
    return _M.timestamp_ms_to_csv(value)
  end
end

return _M

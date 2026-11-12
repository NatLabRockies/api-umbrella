local cidr = require "libcidr-ffi"
local common_validations = require "api-umbrella.web-app.utils.common_validations"
local db_null = require("lapis.db").NULL
local is_array = require "api-umbrella.utils.is_array"
local is_hash = require "api-umbrella.utils.is_hash"
local re_find = ngx.re.find
local validation = require "resty.validation"

local function db_null_optional(default)
  return function(value)
    if value == nil or value == "" or value == db_null then
      return validation.stop, default ~= nil and default or value
    end
    return true, value
  end
end

local function non_null_table()
  return function(value)
    return value ~= db_null and validation.validators.table(value)
  end
end

local function array_table()
  return function(value)
    return value ~= db_null and is_array(value)
  end
end

local function hash_table()
  return function(value)
    return value ~= db_null and is_hash(value)
  end
end

local function array_strings()
  return function(value)
    if validation.validators.array_table(value) then
      for _, str in ipairs(value) do
        if not validation.validators.string(str) then
          return false
        end
      end
    end

    return true
  end
end

local function array_strings_maxlen(length)
  local length_validator = validation.validators.maxlen(length)
  return function(value)
    if validation.validators.array_table(value) then
      for _, str in ipairs(value) do
        if type(str) == "string" and not length_validator(str) then
          return false
        end
      end
    end

    return true
  end
end

local function array_strings_ips()
  return function(value)
    if validation.validators.array_table(value) then
      for _, str in ipairs(value) do
        if type(str) == "string" then
          local _, err = cidr.from_str(str)
          if err then
            return false
          end
        end
      end
    end

    return true
  end
end

local function not_regex(regex, options)
  return function(value)
    local find_from, _, find_err = re_find(value, regex, options)
    if find_err then
      ngx.log(ngx.ERR, "regex error: ", find_err)
    end
    return find_from == nil
  end
end

local function uuid()
  return function(value)
    local find_from, _, find_err = re_find(value, common_validations.uuid, "ijo")
    if find_err then
      ngx.log(ngx.ERR, "regex error: ", find_err)
    end
    return find_from ~= nil
  end
end

local validators = validation.validators
local validators_metatable = getmetatable(validators)

validators.db_null_optional = db_null_optional()
validators_metatable.db_null_optional = db_null_optional

validators.non_null_table = non_null_table()
validators_metatable.non_null_table = non_null_table

validators.array_table = array_table()
validators_metatable.array_table = array_table

validators.hash_table = hash_table()
validators_metatable.hash_table = hash_table

validators.array_strings = array_strings()
validators_metatable.array_strings = array_strings

validators.array_strings_maxlen = array_strings_maxlen()
validators_metatable.array_strings_maxlen = array_strings_maxlen

validators.array_strings_ips = array_strings_ips()
validators_metatable.array_strings_ips = array_strings_ips

validators.not_regex = not_regex()
validators_metatable.not_regex = not_regex

validators.uuid = uuid()
validators_metatable.uuid = uuid

setmetatable(validators, validators_metatable)

return validation

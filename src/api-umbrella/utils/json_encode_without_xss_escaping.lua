local encode_escape_forward_slash = require("cjson").encode_escape_forward_slash
local json_encode = require "api-umbrella.utils.json_encode"
local xpcall_error_handler = require "api-umbrella.utils.xpcall_error_handler"

return function(value)
  encode_escape_forward_slash(false)
  local encode_ok, encoded_value = xpcall(json_encode, xpcall_error_handler, value)
  encode_escape_forward_slash(true)
  if not encode_ok then
    return error(encoded_value)
  end
  return encoded_value
end

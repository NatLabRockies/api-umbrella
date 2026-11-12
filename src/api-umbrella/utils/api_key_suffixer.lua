local API_KEY_SUFFIX_LENGTH = 6

local _M = {}

_M.API_KEY_SUFFIX_LENGTH = API_KEY_SUFFIX_LENGTH

function _M.suffix(api_key)
  return string.sub(api_key, API_KEY_SUFFIX_LENGTH * -1)
end

return _M

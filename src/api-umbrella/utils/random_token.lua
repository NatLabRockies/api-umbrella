local nanoid_generate = require("nanoid.ffi").generate

local DICTIONARY_ALPHANUMERIC = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
-- For public-facing tokens, use a dictionary without lookalikes and attempting
-- to prevent accidental profanity:
-- https://github.com/CyberAP/nanoid-dictionary#nolookalikessafe
local DICTIONARY_NO_LOOK_ALIKES_SAFE = "6789BCDFGHJKLMNPQRTWbcdfghjkmnpqrtwz"

return function(length, no_look_alikes_safe)
  if no_look_alikes_safe then
    return nanoid_generate(length, DICTIONARY_NO_LOOK_ALIKES_SAFE)
  else
    return nanoid_generate(length, DICTIONARY_ALPHANUMERIC)
  end
end

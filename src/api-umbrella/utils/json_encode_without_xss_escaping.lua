local cjson_unsafe = require("cjson").new()
local cjson_encode = cjson_unsafe.encode

cjson_unsafe.encode_escape_forward_slash(false)

-- Mirror json_encode.lua settings.
cjson_unsafe.encode_number_precision(16)

return cjson_encode

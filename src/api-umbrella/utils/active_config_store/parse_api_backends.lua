local cache_computed_api_backend = require "api-umbrella.utils.active_config_store.cache_computed_api_backend"
local cache_computed_api_backend_settings = require "api-umbrella.utils.active_config_store.cache_computed_api_backend_settings"
local cache_computed_api_backend_sub_settings = require "api-umbrella.utils.active_config_store.cache_computed_api_backend_sub_settings"
local config = require("api-umbrella.utils.load_config")()
local deepcopy = require("pl.tablex").deepcopy
local deep_merge_overwrite_arrays = require "api-umbrella.utils.deep_merge_overwrite_arrays"
local stable_object_hash = require "api-umbrella.utils.stable_object_hash"
local xpcall_error_handler = require "api-umbrella.utils.xpcall_error_handler"

local function parse_api(api)
  if not api["id"] then
    api["id"] = stable_object_hash(api)
  end

  cache_computed_api_backend(config, api)
  cache_computed_api_backend_sub_settings(config, api["sub_settings"], deep_merge_overwrite_arrays(deepcopy(config["default_api_backend_settings"]), api["settings"]))
  cache_computed_api_backend_settings(config, api["settings"], config["default_api_backend_settings"])
end

return function(api_backends)
  for _, api in ipairs(api_backends) do
    local ok, err = xpcall(parse_api, xpcall_error_handler, api)
    if not ok then
      ngx.log(ngx.ERR, "failed parsing API config: ", err)
    end
  end
end

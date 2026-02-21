require "config"
require "lapis.features.etlua"
require "api-umbrella.web-app.utils.db_escape_patches"

-- Pre-load modules.
require "api-umbrella.web-app.hooks.init_preload_modules"

local worker_group_init = require("api-umbrella.utils.worker_group").init
worker_group_init()

local config = require("api-umbrella.utils.load_config")()
local find_cmd = require "api-umbrella.utils.find_cmd"
local json_decode = require("cjson").decode
local path_exists = require "api-umbrella.utils.path_exists"
local path_join = require "api-umbrella.utils.path_join"
local readfile = require("pl.utils").readfile

local get_api_umbrella_version = require "api-umbrella.utils.get_api_umbrella_version"
API_UMBRELLA_VERSION = get_api_umbrella_version()

local manifest_path = path_join(config["_embedded_root_dir"], "app/build/dist/web-assets/.vite/manifest.json")
if path_exists(manifest_path) then
  local manifest = json_decode(readfile(manifest_path))
  if manifest and manifest["assets/login.js"] and manifest["assets/login.js"]["file"] then
    LOGIN_JS_FILENAME = manifest["assets/login.js"]["file"]
  else
    ngx.log(ngx.ERR, "could not find login js file path")
  end

  if manifest and manifest["assets/login.js"] and manifest["assets/login.js"]["css"] and #manifest["assets/login.js"]["css"] == 1 then
    LOGIN_CSS_FILENAME = manifest["assets/login.js"]["css"][1]
  else
    ngx.log(ngx.ERR, "could not find login css file path")
  end
else
  ngx.log(ngx.ERR, "could not find login manifest file path")
end

LOCALE_DATA = {}
local locale_paths = find_cmd(path_join(config["_embedded_root_dir"], "app/build/dist/locale"), { "-name", "*.json" })
for _, locale_path in ipairs(locale_paths) do
  local data = json_decode(readfile(locale_path))
  local lang = data["locale_data"]["api-umbrella"][""]["lang"]
  LOCALE_DATA[lang] = data
end

local cjson = require "cjson"
local deep_merge_overwrite_arrays = require "api-umbrella.utils.deep_merge_overwrite_arrays"
local lyaml = require "lyaml"
local split = require("ngx.re").split
local writefile = require("pl.utils").writefile

local json_decode = cjson.decode
local json_null = cjson.null
local yaml_dump = lyaml.dump
local yaml_null = lyaml.null

local function json_nulls_to_yaml_nulls(table)
  if not table then return end

  for key, value in pairs(table) do
    if value == json_null then
      table[key] = yaml_null
    elseif type(value) == "table" then
      table[key] = json_nulls_to_yaml_nulls(value)
    end
  end

  return table
end

return function()
  local vcap_services = os.getenv("VCAP_SERVICES")
  if not vcap_services then
    io.stderr:write("'VCAP_SERVICES' environment variable not defined\n")
    os.exit(1)
  end

  local config_service_name = os.getenv("API_UMBRELLA_CONFIG_VCAP_SERVICE_NAME")
  if not config_service_name then
    io.stderr:write("'API_UMBRELLA_CONFIG_VCAP_SERVICE_NAME' environment variable not defined\n")
    os.exit(1)
  end

  local config = {}

  -- Fetch Cloud Foundry service information from the VCAP_SERVICES environment
  -- variable.
  local vcap_services_data = json_decode(vcap_services)

  -- Set SES credentails from service if available.
  if vcap_services_data["aws-ses"] and vcap_services_data["aws-ses"][1] and vcap_services_data["aws-ses"][1]["credentials"] then
    local credentials = vcap_services_data["aws-ses"][1]["credentials"]

    local configuration_set
    if credentials["configuration_set_arn"] then
      local parts = split(credentials["configuration_set_arn"], "/")
      configuration_set = parts[2]
    end

    deep_merge_overwrite_arrays(config, json_nulls_to_yaml_nulls({
      web = {
        mailer = {
          smtp_settings = {
            address = credentials["smtp_server"],
            port = 465,
            ssl = true,
            ssl_verify = true,
            ssl_host = credentials["smtp_server"],
            domain = credentials["domain"],
            authentication = "login",
            user_name = credentials["smtp_user"],
            password = credentials["smtp_password"],
          },
          headers = {
            ["X-SES-CONFIGURATION-SET"] = configuration_set,
          },
        },
      },
      envoy = {
        smtp_proxy = {
          endpoint = {
            host = credentials["smtp_server"],
            port = 465,
          },
        },
      },
    }))
  end

  -- Find our secret configuration (via a user provided service), and merge that
  -- on top of the existing API Umbrella config.
  local found_config_service = false
  for _, service in ipairs(vcap_services_data["user-provided"]) do
    if service["name"] == config_service_name then
      found_config_service = true
      deep_merge_overwrite_arrays(config, json_nulls_to_yaml_nulls(service["credentials"]))
    end
  end

  if not found_config_service then
    io.stderr:write("Did not find the '" .. config_service_name .. "' service in VCAP_SERVICES\n")
    os.exit(1)
  end

  local config_path = os.getenv("API_UMBRELLA_CONFIG") or "/etc/api-umbrella/api-umbrella.yml"
  writefile(config_path, yaml_dump({ config }))
end

local active_config_exists = require("api-umbrella.proxy.stores.active_config_store").exists
local config = require("api-umbrella.utils.load_config")()
local http = require "resty.http"
local json_encode = require "api-umbrella.utils.json_encode"
local opensearch = require "api-umbrella.utils.opensearch"

local jobs_dict = ngx.shared.jobs
local opensearch_query = opensearch.query
local ngx_var = ngx.var

local function status_response(quick, ignore_trafficserver)
  local response = {
    status = "red",
    details = {
      apis_config = "red",
      cache_server = "red"
    },
  }

  -- Check to see if the APIs have been loaded.
  if active_config_exists() then
    response["details"]["apis_config"] = "green"
  else
    ngx.log(ngx.ERR, "no active config exists")
  end

  local httpc = http.new()
  httpc:set_timeout(3000)

  local res, err = httpc:request_uri("http://127.0.0.1:" .. config["trafficserver"]["port"] .. "/_trafficserver-health/nocache/1", {
    headers = {
      ["Host"] = "api-umbrella-trafficserver-health.internal",
    },
  })
  if err then
    ngx.log(ngx.ERR, "failed to fetch trafficserver health: ", err)
    if ignore_trafficserver then
      response["details"]["cache_server"] = "yellow"
    end
  elseif res.status == 200 then
    response["details"]["cache_server"] = "green"
  end

  if quick then
    if response["details"]["apis_config"] == "green" and response["details"]["cache_server"] == "green" then
      response["status"] = "green"
    elseif response["details"]["apis_config"] == "green" and response["details"]["cache_server"] == "yellow" then
      response["status"] = "yellow"
    end

    return response
  end

  response["details"]["analytics_db"] = "red"
  response["details"]["analytics_db_setup"] = "red"
  response["details"]["web_app"] = "red"

  -- Check the health of the OpenSearch cluster
  res, err = opensearch_query("/_cluster/health")
  if err then
    ngx.log(ngx.ERR, "failed to fetch cluster health from opensearch: ", err)
  elseif res.body_json then
    local opensearch_health = res.body_json
    response["details"]["analytics_db"] = opensearch_health["status"]

    -- Check to see if the OpenSearch index aliases have been setup.
    local created = jobs_dict:get("opensearch_templates_created")
    if created then
      response["details"]["analytics_db_setup"] = "green"
    end
  end

  res, err = httpc:request_uri("http://127.0.0.1:" .. config["web"]["port"] .. "/_web-app-health")
  if err then
    ngx.log(ngx.ERR, "failed to fetch web app: ", err)
  elseif res.status == 200 then
    response["details"]["web_app"] = "green"
  end

  -- If everything looks good on the components, then mark our overall status a green.
  --
  -- Note: We accept OpenSearch being in yellow status as long as the aliases
  -- are setup, since on very first alias creation (but prior to indexing any
  -- content), OpenSearch seems to get stuck in the yellow status, even though
  -- everything appears operational (but then it becomes green once content
  -- starts indexing).
  if response["details"]["apis_config"] == "green" and response["details"]["cache_server"] == "green" and (response["details"]["analytics_db"] == "yellow" or response["details"]["analytics_db"] == "green") and response["details"]["analytics_db_setup"] == "green" and response["details"]["web_app"] == "green" then
    response["status"] = "green"
  elseif response["details"]["apis_config"] == "green" and response["details"]["cache_server"] == "green" then
    response["status"] = "yellow"
  end

  return response
end

-- By default, check the health status and return it immediately.
--
-- If a "wait_for_status" query param is passed in, then loop until this status
-- becomes true, or the request times out (defaults to 50 seconds).
--
-- "wait_for_status" can be "green", "yellow", or "red". The request will wait
-- until this status *or better* is met. green > yellow > red, so
-- wait_for_status=yellow will return if the status is actually yellow.
local response
local wait_for_status = ngx_var.arg_wait_for_status
local quick = ngx_var.arg_quick == "true"
local ignore_trafficserver = ngx_var.arg_ignore_trafficserver == "true"
if not wait_for_status then
  response = status_response(quick, ignore_trafficserver)
else
  -- Validate the wait_for_status param.
  if wait_for_status ~= "green" and wait_for_status ~= "yellow" and wait_for_status ~= "red" then
    ngx.status = 422
    ngx.header["Content-Type"] = "application/json"
    ngx.say(json_encode({
      error = "Invalid wait_for_status argument (" .. (tostring(wait_for_status) or "") .. ")",
    }))
    return ngx.exit(ngx.HTTP_OK)
  end

  -- Validate the wait_timeout param (defaults to 50).
  local wait_timeout = tonumber(ngx_var.arg_wait_timeout or 50)
  if not wait_timeout then
    ngx.status = 422
    ngx.header["Content-Type"] = "application/json"
    ngx.say(json_encode({
      error = "Invalid wait_timeout argument (" .. (tostring(wait_timeout) or "") .. ")",
    }))
    return ngx.exit(ngx.HTTP_OK)
  end

  -- Loop until the status is met or we timeout.
  local timeout_at = ngx.now() + wait_timeout
  while true do
    response = status_response(quick)

    -- Break out of loop if the status (or better) is met.
    local status = response["status"]
    if wait_for_status == status then
      break
    elseif wait_for_status == "yellow" and status == "green" then
      break
    elseif wait_for_status == "red" and (status == "green" or status == "yellow") then
      break
    end

    -- If we've timed out, still return the last status in the response, but
    -- with an HTTP error code to indicate it wasn't met.
    if ngx.now() > timeout_at then
      ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
      break
    end

    ngx.sleep(0.5)
  end
end

-- Return an error HTTP status code if the status is red.
local json_response = json_encode(response)
if response["status"] == "red" then
  ngx.log(ngx.ERR, "Unhealthy health check: ", json_response)
  ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
end

ngx.header["Content-Type"] = "application/json"
ngx.say(json_response)

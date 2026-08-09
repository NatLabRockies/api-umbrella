local aws_sign = require("api-umbrella.utils.aws_signing_v4").sign_resty_http_request
local config = require("api-umbrella.utils.load_config")()
local http = require "resty.http"
local is_empty = require "api-umbrella.utils.is_empty"
local json_decode = require("cjson").decode
local json_encode = require "api-umbrella.utils.json_encode"

local encode_base64 = ngx.encode_base64
local server = config["opensearch"]["_first_server"]

local _M = {}

function _M.query(path, options)
  local httpc = http.new()

  if config["http_proxy"] or config["https_proxy"] then
    httpc:set_proxy_options({
      http_proxy = config["http_proxy"],
      https_proxy = config["https_proxy"],
    })
  end

  if not options then
    options = {}
  end

  if options["server"] then
    server = options["server"]
    options["server"] = nil
  end

  options["path"] = path

  if not options["headers"] then
    options["headers"] = {}
  end

  if (server["user"] or server["password"]) and not options["headers"]["Authorization"] then
    options["headers"]["Authorization"] = "Basic " .. encode_base64((server["user"] or "") .. ":" .. (server["password"] or ""))
  end

  if options["body"] and type(options["body"]) == "table" then
    options["body"] = json_encode(options["body"])

    if not options["headers"]["Content-Type"] then
      options["headers"]["Content-Type"] = "application/json"
    end
  end

  local connect_ok, connect_err = httpc:connect({
    scheme = server["scheme"],
    host = server["host"],
    port = server["port"],
    ssl_server_name = server["host"],
    ssl_verify = true,
  })
  if not connect_ok then
    httpc:close()
    return nil, "opensearch connect error: " .. (connect_err or "")
  end

  if config["fluent_bit"]["outputs"]["opensearch"]["aws_auth"] then
    aws_sign(
      config["fluent_bit"]["outputs"]["opensearch"]["aws_region"],
      config["fluent_bit"]["outputs"]["opensearch"]["aws_service_name"],
      config["fluent_bit"]["aws_access_key_id"],
      config["fluent_bit"]["aws_secret_access_key"],
      httpc,
      options
    )
  end

  local res, err = httpc:request(options)
  if err then
    httpc:close()
    return nil, "opensearch request error: " .. (err or "")
  end

  local body, body_err = res:read_body()
  if body_err then
    httpc:close()
    return nil, "opensearch read body error: " .. (body_err or "")
  end
  res["body"] = body

  local keepalive_ok, keepalive_err = httpc:set_keepalive()
  if not keepalive_ok then
    httpc:close()
    return nil, "opensearch keepalive error: " .. (keepalive_err or "")
  end

  if res.status >= 300 and res.status ~= 404 then
    return nil, "Unsuccessful response (" .. (res.status or "") .. "): " .. (body or "")
  else
    if res.headers["Content-Type"] and string.sub(res.headers["Content-Type"], 1, 16) == "application/json" and not is_empty(body) then
      res["body_json"] = json_decode(body)

      if res["body_json"]["_shards"] and not is_empty(res["body_json"]["_shards"]["failures"]) then
        return nil, "Unsuccessful response: " .. (body or "")
      end
    end

    return res
  end
end

return _M

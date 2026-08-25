local http = require "resty.http"
local http_headers = require "resty.http_headers"
local nettle_hmac = require "resty.nettle.hmac"
local resty_sha256 = require "resty.sha256"
local table_copy = require("pl.tablex").copy
local to_hex = require("resty.string").to_hex

local decode_args = ngx.decode_args
local escape_uri = ngx.escape_uri
local gsub = ngx.re.gsub
local now = ngx.now
local os_date = os.date
local resty_http_user_agent = http._USER_AGENT
local string_lower = string.lower
local string_sub = string.sub
local string_upper = string.upper
local transfer_encoding_is_chunked = http.transfer_encoding_is_chunked

local EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
local UNSIGNED_HEADERS = {
  authorization = 1,
  expect = 1,
  ["x-amzn-trace-id"] = 1
}
local EXPECTING_BODY = {
  POST = true,
  PUT = true,
  PATCH = true,
}

local _M = {
  EMPTY_SHA256 = EMPTY_SHA256,
}

local function hmac(secret_key, value)
  assert(secret_key)
  assert(value)

  local hmac_sha256 = nettle_hmac.sha256.new(secret_key)
  hmac_sha256:update(value)
  local binary = hmac_sha256:digest()

  return binary
end

local function sha256_hexdigest(value)
  local sha256 = resty_sha256:new()
  sha256:update(value or "")
  return to_hex(sha256:final())
end

local function canonical_header_name(name)
  return string_lower(name)
end

local function canonical_header_value(value)
  local string_value = value
  if type(value) == "table" then
    string_value = table.concat(value, ",")
  end

  return gsub(gsub(string_value, [[\s+]], " ", "jo"), [[(^\s+|\s+$)]], "", "jo")
end

local function escape_uri_component(value)
  if(value == true) then
    return ""
  else
    return escape_uri(value or "")
  end
end

local function get_signature_headers(datetime, request_body)
  local content_sha256
  if request_body and request_body ~= "" then
    content_sha256 = sha256_hexdigest(request_body)
  else
    content_sha256 = EMPTY_SHA256
  end

  local signature_headers = {
    ["X-Amz-Date"] = datetime,
    ["X-Amz-Content-Sha256"] = content_sha256,
  }

  return signature_headers
end

local function add_signature_headers(request_headers, signature_headers)
  local headers = table_copy(request_headers)
  for name, value in pairs(signature_headers) do
    headers[name] = value
  end

  return headers
end

local function get_canonical_headers(pre_signing_headers)
  local canonical_headers = {}
  for name, value in pairs(pre_signing_headers) do
    local canonical_name = canonical_header_name(name)
    if not UNSIGNED_HEADERS[canonical_name] then
      local canonical_value = canonical_header_value(value)
      canonical_headers[canonical_name] = canonical_value
    end
  end

  return canonical_headers
end

local function get_canonical_headers_string(canonical_headers)
  local canonical = {}
  for name, value in pairs(canonical_headers) do
    table.insert(canonical, name .. ":" .. value)
  end

  table.sort(canonical)
  return table.concat(canonical, "\n") .. "\n"
end

local function get_signed_headers_string(canonical_headers)
  local signed = {}
  for name, _ in pairs(canonical_headers) do
    table.insert(signed, name)
  end

  table.sort(signed)
  return table.concat(signed, ";")
end

local function get_canonical_uri_path(uri_path)
  if not uri_path or uri_path == "" then
    return "/"
  else
    return gsub(escape_uri(uri_path), [[%2F]], "/", "ijo")
  end
end

local function get_canonical_query_string(uri_args)
  if not uri_args then
    return ""
  end

  local uri_args_table = uri_args
  if type(uri_args) == "string" then
    local err
    uri_args_table, err = decode_args(uri_args)
    if err then
      ngx.log(ngx.ERR, "Error decoding args: ", err)
      return ""
    end
  end

  local canonical = {}
  for name, value in pairs(uri_args_table) do
    if type(value) == "table" then
      for _, multi_value in ipairs(value) do
        table.insert(canonical, escape_uri_component(name) .. "=" .. escape_uri_component(multi_value))
      end
    else
      table.insert(canonical, escape_uri_component(name) .. "=" .. escape_uri_component(value))
    end
  end

  table.sort(canonical)
  return table.concat(canonical, "&")
end

local function get_canonical_request_string(request_method, uri_path, uri_args, canonical_headers, signed_headers_string)
  return table.concat({
    request_method,
    get_canonical_uri_path(uri_path),
    get_canonical_query_string(uri_args),
    get_canonical_headers_string(canonical_headers),
    signed_headers_string,
    canonical_headers["x-amz-content-sha256"],
  }, "\n")
end

local function get_credential_scope(aws_region, aws_service, date)
  return table.concat({
    date,
    aws_region,
    aws_service,
    "aws4_request",
  }, "/")
end

local function get_string_to_sign(datetime, credential_scope, canonical_request_string)
  return table.concat({
    "AWS4-HMAC-SHA256",
    datetime,
    credential_scope,
    sha256_hexdigest(canonical_request_string),
  }, "\n")
end

local function get_signature(aws_region, aws_service, aws_secret_access_key, date, string_to_sign)
  local date_key = hmac("AWS4" .. aws_secret_access_key, date)
  local date_region_key = hmac(date_key, aws_region)
  local date_region_service_key = hmac(date_region_key, aws_service)
  local signing_key = hmac(date_region_service_key, "aws4_request")
  return to_hex(hmac(signing_key, string_to_sign))
end

local function get_authorization_header_value(aws_access_key_id, credential_scope, signed_headers_string, signature)
  return table.concat({
    "AWS4-HMAC-SHA256 Credential=" .. aws_access_key_id .. "/" .. credential_scope,
    "SignedHeaders=" .. signed_headers_string,
    "Signature=" .. signature,
  }, ",")
end

function _M.generate_signature_headers(aws_region, aws_service, aws_access_key_id, aws_secret_access_key, request_method, uri_path, uri_args, request_headers, request_body)
  local datetime = os_date("!%Y%m%dT%H%M%SZ", now())
  local date = string_sub(datetime, 1, 8)

  local signature_headers = get_signature_headers(datetime, request_body)
  local pre_signing_headers = add_signature_headers(request_headers, signature_headers)
  local canonical_headers = get_canonical_headers(pre_signing_headers)
  local signed_headers_string = get_signed_headers_string(canonical_headers)
  local canonical_request_string = get_canonical_request_string(request_method, uri_path, uri_args, canonical_headers, signed_headers_string)
  local credential_scope = get_credential_scope(aws_region, aws_service, date)
  local string_to_sign = get_string_to_sign(datetime, credential_scope, canonical_request_string)
  local signature = get_signature(aws_region, aws_service, aws_secret_access_key, date, string_to_sign)
  local authorization_value = get_authorization_header_value(aws_access_key_id, credential_scope, signed_headers_string, signature)
  signature_headers["Authorization"] = authorization_value

  return signature_headers
end

local function prepare_resty_http_request(connection, params)
  -- Add headers to the request that lua-resty-http will eventually add later:
  -- https://github.com/ledgetech/lua-resty-http/blob/v0.17.1/lib/resty/http.lua#L666-L742
  --
  -- While not ideal to duplicate all of this logic, there's not really a way
  -- to hook into a later phase of lua-resty-http, so we need to replicate this
  -- logic so we know all of the headers that will eventually be set so that we
  -- can sign the request accounting for all headers.
  if not params.method then
    params.method = "GET"
  end
  if not params.path then
    params.path = "/"
  end
  if not params.version then
    params.version = 1.1
  end
  local body = params.body
  local headers = http_headers.new()
  local params_headers = params.headers or {}
  for k, v in pairs(params_headers) do
      headers[k] = v
  end

  if not headers["Proxy-Authorization"] then
    headers["Proxy-Authorization"] = connection.http_proxy_auth
  end

  do
    local is_chunked = transfer_encoding_is_chunked(headers)
    if is_chunked then
      headers["Content-Length"] = nil
    elseif not headers["Content-Length"] then
      local body_type = type(body)
      if body_type == "function" then
        return nil, "Request body is a function but a length or chunked encoding is not specified"
      elseif body_type == "table" then
        local length = 0
        for _, v in ipairs(body) do
          length = length + #tostring(v)
        end
        headers["Content-Length"] = length
      elseif body == nil and EXPECTING_BODY[string_upper(params.method)] then
        headers["Content-Length"] = 0
      elseif body ~= nil then
        headers["Content-Length"] = #tostring(body)
      end
    end
  end

  if not headers["Host"] then
    if (string_sub(connection.host, 1, 5) == "unix:") then
      return nil, "Unable to generate a useful Host header for a unix domain socket. Please provide one."
    end
    if connection.port then
      if connection.ssl and connection.port ~= 443 then
        headers["Host"] = connection.host .. ":" .. connection.port
      elseif not connection.ssl and connection.port ~= 80 then
        headers["Host"] = connection.host .. ":" .. connection.port
      else
        headers["Host"] = connection.host
      end
    else
      headers["Host"] = connection.host
    end
  end
  if not headers["User-Agent"] then
    headers["User-Agent"] = resty_http_user_agent
  end
  if params.version == 1.0 and not headers["Connection"] then
    headers["Connection"] = "Keep-Alive"
  end

  params.headers = headers
end

function _M.sign_resty_http_request(aws_region, aws_service, aws_access_key_id, aws_secret_access_key, resty_http_connection, resty_http_params)
  prepare_resty_http_request(resty_http_connection, resty_http_params)

  local request_method = resty_http_params["method"]
  local uri_path = resty_http_params["path"]
  local uri_args = resty_http_params["query"]
  local request_headers = resty_http_params["headers"]
  local request_body = resty_http_params["body"]

  local signature_headers = _M.generate_signature_headers(aws_region, aws_service, aws_access_key_id, aws_secret_access_key, request_method, uri_path, uri_args, request_headers, request_body)
  for name, value in pairs(signature_headers) do
    resty_http_params["headers"][name] = value
  end
end

return _M

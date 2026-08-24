local config = require("api-umbrella.utils.load_config")()
local deep_merge_overwrite_arrays = require "api-umbrella.utils.deep_merge_overwrite_arrays"
local escape_csv = require "api-umbrella.utils.escape_csv"
local escape_html = require "api-umbrella.utils.escape_html"
local extension = require("pl.path").extension
local http_headers = require "api-umbrella.utils.http_headers"
local httpsify_current_url = require "api-umbrella.utils.httpsify_current_url"
local string_template = require "api-umbrella.utils.string_template"
local utils = require "api-umbrella.proxy.utils"

local ngx_exit = ngx.exit
local ngx_header = ngx.header
local ngx_print = ngx.print
local ngx_var = ngx.var
local quote_json = ndk.set_var.set_quote_json_str
local redirect = ngx.redirect

local supported_media_types = {
  {
    format = "json",
    media_type = "application",
    media_subtype = "json",
  },
  {
    format = "xml",
    media_type = "application",
    media_subtype = "xml",
  },
  {
    format = "xml",
    media_type = "text",
    media_subtype = "xml",
  },
  {
    format = "csv",
    media_type = "text",
    media_subtype = "csv",
  },
  {
    format = "html",
    media_type = "text",
    media_subtype = "html",
  },
}

local supported_formats = {}
for _, media in ipairs(supported_media_types) do
  if not supported_formats[media["format"]] then
    supported_formats[media["format"]] = media["media_type"] .. "/" .. media["media_subtype"]
  end
end

local function request_format(ngx_ctx)
  local request_path = ngx_ctx.uri_path
  if request_path then
    local format = extension(request_path)
    if format then
      format = string.sub(format, 2)
      if supported_formats[format] then
        return format, supported_formats[format]
      end
    end
  end

  local format_arg = ngx_var.arg_format
  if format_arg then
    if supported_formats[format_arg] then
      return format_arg, supported_formats[format_arg]
    end
  end

  local accept_header = ngx_var.http_accept
  if accept_header then
    local media = http_headers.preferred_accept(accept_header, supported_media_types)
    if media then
      return media["format"], media["media_type"] .. "/" .. media["media_subtype"]
    end
  end

  return "json", supported_formats["json"]
end

return function(ngx_ctx, denied_code, settings, extra_data)
  -- Store the gatekeeper rejection code for logging.
  ngx_ctx.gatekeeper_denied_code = denied_code

  -- Redirect "not_found" errors to HTTPS.
  --
  -- Since these errors aren't subject to an API Backend's HTTPS requirements
  -- (where we might return the "https_required" error), this helps ensure that
  -- requests to unknown location (neither API or website backend) are
  -- redirected to HTTPS like the rest of our non-API content. This ensures
  -- HTTPS redirects are in place for the root request on custom domains
  -- without a website or API at the root.
  if denied_code == "not_found" and config["router"]["redirect_not_found_to_https"] then
    if ngx_ctx.protocol ~= "https" then
      return redirect(httpsify_current_url(ngx_ctx), ngx.HTTP_MOVED_PERMANENTLY)
    end
  end

  if denied_code == "redirect_https" then
    return redirect(httpsify_current_url(ngx_ctx), ngx.HTTP_MOVED_PERMANENTLY)
  end

  if not settings then
    settings = config["_default_api_backend_settings"]
  end

  -- Try to determine the format of the request (JSON, XML, etc), so we can
  -- attempt to match our response to the expected format.
  local format, content_type = request_format(ngx_ctx)

  -- Fetch the error data for use with this error type.
  local error_data = settings["_error_data"][denied_code]

  local new_error_data_vars = false

  if not error_data["base_url"] then
    error_data["base_url"] = utils.base_url(ngx_ctx)

    -- Support legacy camel-case capitalization of variables. Moving forward,
    -- we're trying to clean things up and standardize on snake_case.
    if not error_data["baseUrl"] then
      error_data["baseUrl"] = error_data["base_url"]
    end

    new_error_data_vars = true
  end

  -- Add any extra data we might be passing internally.
  if extra_data then
    deep_merge_overwrite_arrays(error_data, extra_data)
    new_error_data_vars = true
  end

  if new_error_data_vars then
    for key, value in pairs(error_data) do
      if type(value) == "string" then
        error_data[key] = string_template(value, error_data)
      end
    end
  end

  -- Determine the status code for the HTTP response.
  local status_code = error_data["status_code"] or 500

  -- Fetch the template for rendering the different formats of error messages
  -- (JSON, XML, etc).
  local template = settings["_error_templates"][format]

  local escape_callback
  if format == "json" then
    escape_callback = quote_json
  elseif format == "xml" then
    escape_callback = escape_html
  elseif format == "html" then
    escape_callback = escape_html
  elseif format == "csv" then
    escape_callback = escape_csv
  end

  -- Render the error message, substituting the variables.
  local output = string_template(template, error_data, escape_callback)

  -- Allow all errors to be loaded over CORS (in case any underlying APIs are
  -- expected to be accessed over CORS then we want to make sure errors are
  -- also allowed via CORS).
  ngx_header["Access-Control-Allow-Origin"] = "*"

  if error_data["cache_control"] then
    ngx_header["Cache-Control"] = error_data["cache_control"]
  end

  ngx.status = status_code
  ngx_header.content_type = content_type
  ngx_print(output)
  return ngx_exit(ngx.HTTP_OK)
end

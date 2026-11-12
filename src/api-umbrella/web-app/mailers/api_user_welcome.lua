local config = require("api-umbrella.utils.load_config")()
local escape_html = require("lapis.html").escape
local etlua = require "etlua"
local is_empty = require "api-umbrella.utils.is_empty"
local known_domains = require "api-umbrella.web-app.utils.known_domains"
local mail = require "api-umbrella.utils.mail"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local table_copy = require("pl.tablex").copy
local url_parse = require "api-umbrella.utils.url_parse"

local re_sub = ngx.re.sub

local template_html, template_html_err = etlua.compile([[
<!DOCTYPE html>
<html>
  <head>
    <style type="text/css">
      p {
        margin: 0px 0px 1rem 0px;
      }

      code.signup-key {
        font-size: 1.25rem;
        font-weight: bold;
        background-color: #fcfcfc;
        border: 2px solid #e6e6e6;
        border-radius: 0.25rem;
        display: inline-block;
        color: #e41d3d;
        padding: 0.375rem 0.5rem;
        word-break: break-all;
      }

      .signup-footer {
        margin-top: 2rem;
        padding-top: 1rem;
        font-size: 0.875rem;
        color: #3d4551;
        border-top: 2px solid #a9aeb1;
      }
    </style>
  </head>
  <body>
    <p><%- greeting %></p>

    <p>
      <code class="signup-key"><%- api_key %></code>
    </p>

    <p><%- example_instruction %></p>

    <div class="signup-footer">
      <p><%- support %></p>
      <p>
        <%- account_email %><br>
        <%- account_id %>
      </p>
    </div>
  </body>
</html>
]])
if template_html_err then
  ngx.log(ngx.ERR, "template compile error: ", template_html_err)
end

local template_text, template_text_err = etlua.compile([[
<%- greeting %>

<%- api_key %>

<%- example_instruction %>

---

<%- support %>

<%- account_email %>
<%- account_id %>
]])
if template_text_err then
  ngx.log(ngx.ERR, "template compile error: ", template_text_err)
end

return function(api_user, options)
  if not options then
    options = {}
  end

  local api_key = api_user:api_key_decrypted()

  local host
  if api_user.registration_origin then
    local origin =  known_domains.sanitized_url(api_user.registration_origin)
    if origin then
      local parsed, parse_err = url_parse(origin)
      if parse_err then
        ngx.log(ngx.ERR, "error parsing registration_origin: ", api_user.registration_origin, " error: ", parse_err)
      elseif parsed and parsed["host"] then
        host = parsed["host"]
      end
    end
  end
  if not host then
    host = config["web"]["default_host"]
  end

  local from = options["email_from_address"]
  if is_empty(from) then
    from = "noreply@" .. config["web"]["default_host"]
  end
  if not string.find(from, "<", nil, true) then
    from = host .. " API Keys <" .. from .. ">"
  end

  local data = {
    greeting = t("You are receiving this email to confirm the creation of an API key at %s. If you did not request this, please disregard this email. Your API key for %s is:"),
    api_key = api_key,
    account_email = t("Account Email: %s"),
    account_id = t("Account ID: %s"),
    example_api_url = options["example_api_url"],
    example_api_url_formatted_html = options["example_api_url_formatted_html"],
    example_instruction = t("You can start using this key to make web service requests by referring to the relevant agency's API documentation. This API key is for your use and should not be shared."),
    support = t("For additional support, please %s. When contacting us, please tell us what API you're accessing and provide the following account details so we can quickly find you:"),
  }

  local data_text = table_copy(data)
  data_text["hi"] = data["hi"]
  data_text["greeting"] = string.format(data["greeting"], host, api_user.email)
  data_text["account_email"] = string.format(data["account_email"], api_user.email)
  data_text["account_id"] = string.format(data["account_id"], api_user.id)
  if options["contact_url"] then
    data_text["support"] = string.format(data["support"], t("contact us") .. " ( " .. re_sub(options["contact_url"], "^mailto:", "", "jo") .. " )")
  else
    data_text["support"] = string.format(data["support"], t("contact us"))
  end

  local data_html = table_copy(data)
  data_html["hi"] = data["hi"]
  data_html["greeting"] = string.format(data["greeting"], escape_html(host), "<strong>" .. escape_html(api_user.email) .."</strong>")
  data_html["account_email"] = string.format(data["account_email"], escape_html(api_user.email))
  data_html["account_id"] = string.format(data["account_id"], escape_html(api_user.id))
  if options["contact_url"] then
    data_html["support"] = string.format(data["support"], string.format([[<a href="%s">%s</a>]], escape_html(options["contact_url"]), t("contact us")))
  else
    data_html["support"] = string.format(data["support"], t("contact us"))
  end

  local mailer, mailer_err = mail()
  if not mailer then
    return nil, mailer_err
  end

  local ok, send_err = mailer:send({
    headers = config["web"]["mailer"]["headers"],
    from = from,
    to = { api_user.email },
    subject = string.format(t("Your %s API key"), host),
    text = template_text(data_text),
    html = template_html(data_html),
  })
  if not ok then
    return nil, send_err
  end

  return true
end

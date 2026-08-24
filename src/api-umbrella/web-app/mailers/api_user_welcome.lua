local config = require("api-umbrella.utils.load_config")()
local escape_html = require("lapis.html").escape
local etlua = require "etlua"
local is_empty = require "api-umbrella.utils.is_empty"
local mail = require "api-umbrella.utils.mail"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local table_copy = require("pl.tablex").copy

local re_sub = ngx.re.sub

local template_html, template_html_err = etlua.compile([[
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" "http://www.w3.org/TR/REC-html40/loose.dtd">
<html>
  <head>
    <style type="text/css">
      p, li, pre {
        font-size: 15px;
      }

      code.signup-key {
        font-size: 18px;
        font-weight: bold;
        margin-bottom: 32px;
        background-color: #f7f7f9;
        border: 1px solid  #e1e1e8;
        display: inline-block;
        color: #dd1144;
        padding: 2px 4px;
      }

      pre {
        background-color: #f7f7f9;
        border: 1px solid  #e1e1e8;
        padding: 2px 4px;
        word-break: break-all;
        word-wrap: break-word;
      }

      h2 {
        font-size: 18px;
      }

      .signup-footer {
        margin-top: 32px;
        font-size: 12px;
        background-color: #f5f5f5;
        color: #555;
        padding: 2px 4px;
      }

      .signup-footer p {
        color: #555;
        font-size: 12px;
        margin: 0px 0px 8px 0px;
        padding: 0px;
      }
    </style>
  </head>
  <body>
    <p><%- hi %></p>

    <p><%- greeting %></p>
    <code class="signup-key"><%- api_key %></code>

    <p><%- example_instruction %></p>

    <div class="signup-footer">
      <p><%- support %></p>
      <%- account_email %><br>
      <%- account_id %>
    </div>
  </body>
</html>
]])
if template_html_err then
  ngx.log(ngx.ERR, "template compile error: ", template_html_err)
end

local template_text, template_text_err = etlua.compile([[
<%- hi %>

<%- greeting %>

<%- api_key %>

<%- example_instruction %>

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

  local from = options["email_from_address"]
  if is_empty(from) then
    from = "noreply@" .. config["web"]["default_host"]
  end

  local data = {
    hi = t("Hi,"),
    greeting = t("You are receiving this email to confirm the creation of an API key. If you did not request this, please disregard this email. Your API key for %s is:"),
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
  data_text["greeting"] = string.format(data["greeting"], api_user.email)
  data_text["account_email"] = string.format(data["account_email"], api_user.email)
  data_text["account_id"] = string.format(data["account_id"], api_user.id)
  if options["contact_url"] then
    data_text["support"] = string.format(data["support"], t("contact us") .. " ( " .. re_sub(options["contact_url"], "^mailto:", "", "jo") .. " )")
  else
    data_text["support"] = string.format(data["support"], t("contact us"))
  end

  local data_html = table_copy(data)
  data_html["hi"] = data["hi"]
  data_html["greeting"] = string.format(data["greeting"], "<strong>" .. escape_html(api_user.email) .."</strong>")
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
    subject = t("Your API key"),
    text = template_text(data_text),
    html = template_html(data_html),
  })
  if not ok then
    return nil, send_err
  end

  return true
end

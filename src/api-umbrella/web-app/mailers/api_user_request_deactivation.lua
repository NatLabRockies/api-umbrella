local config = require("api-umbrella.utils.load_config")()
local etlua = require "etlua"
local mail = require "api-umbrella.utils.mail"
local t = require("api-umbrella.web-app.utils.gettext").gettext

local template_text, template_text_err = etlua.compile([[
<%- instruction %>

<%- url %>

<%- instruction_2 %>
]])
if template_text_err then
  ngx.log(ngx.ERR, "template compile error: ", template_text_err)
end

return function(api_user, url, host)
  local data = {
    instruction = string.format(t("We received a request to deactivate your API key ending in \"%s\". To confirm you'd like to deactivate your API key, visit the link below and confirm your request:"), api_user.api_key_suffix),
    url = url,
    instruction_2 = t("Your API key is still active and will not be deactivated until you follow the link above and complete the final confirmation step."),
  }

  local mailer, mailer_err = mail()
  if not mailer then
    return nil, mailer_err
  end

  local ok, send_err = mailer:send({
    headers = config["web"]["mailer"]["headers"],
    from = host .. " API Keys <noreply@" .. config["web"]["default_host"] .. ">",
    to = { api_user.email },
    subject = string.format(t("Confirm %s API key deactivation request"), host),
    text = template_text(data),
  })
  if not ok then
    return nil, send_err
  end

  return true
end

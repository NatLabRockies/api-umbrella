local Admin = require "api-umbrella.web-app.models.admin"
local admin_invite_mailer = require "api-umbrella.web-app.mailers.admin_invite"
local admin_policy = require "api-umbrella.web-app.policies.admin_policy"
local capture_errors_json_full = require("api-umbrella.web-app.utils.capture_errors").json_full
local config = require("api-umbrella.utils.load_config")()
local csrf_validate_token_or_admin_token_filter = require("api-umbrella.web-app.utils.csrf").validate_token_or_admin_token_filter
local datatables = require "api-umbrella.web-app.utils.datatables"
local dbify_json_nulls = require "api-umbrella.web-app.utils.dbify_json_nulls"
local json_response = require "api-umbrella.web-app.utils.json_response"
local require_admin = require "api-umbrella.web-app.utils.require_admin"
local respond_to = require "api-umbrella.web-app.utils.respond_to"
local validation_ext = require "api-umbrella.web-app.utils.validation_ext"
local wrapped_json_params = require "api-umbrella.web-app.utils.wrapped_json_params"

local _M = {}

local function send_invite_email(self, admin)
  local send_email = false
  if self.params and type(self.params["options"]) == "table" and tostring(self.params["options"]["send_invite_email"]) == "true" then
    send_email = true
  end

  -- For the admin tool, it's easier to have this attribute on the user model,
  -- rather than options.
  if not send_email and self.params and type(self.params["admin"]) == "table" and tostring(self.params["admin"]["send_invite_email"]) == "true" then
    send_email = true
  end

  if not send_email then
    return nil
  end

  -- Don't resend invites to admins that are already signed in.
  if admin.current_sign_in_at then
    return nil
  end

  local token
  if config["web"]["admin"]["auth_strategies"]["_enabled"]["local"] then
    token = admin:set_invite_reset_password_token()
  end

  local ok, err = admin_invite_mailer(admin, token)
  if not ok then
    ngx.log(ngx.ERR, "mail error: ", err)
  end
end

function _M.index(self)
  return datatables.index(self, Admin, {
    where = {
      admin_policy.authorized_query_scope(self.current_admin),
    },
    search_fields = {
      "name",
      "email",
      "username",
    },
    order_fields = {
      "username",
      "email",
      "current_sign_in_at",
      "created_at",
      "updated_at",
    },
    preload = {
      "authorized_groups",
    },
    csv_filename = "admins",
  })
end

function _M.show(self)
  self.admin:authorize()
  local response = {
    admin = self.admin:as_json(),
  }

  return json_response(self, response)
end

function _M.create(self)
  local admin = assert(Admin:authorized_create(_M.admin_params(self)))
  local response = {
    admin = admin:as_json(),
  }

  send_invite_email(self, admin)

  self.res.status = 201
  return json_response(self, response)
end

function _M.update(self)
  self.admin:authorized_update(_M.admin_params(self))
  local response = {
    admin = self.admin:as_json(),
  }

  send_invite_email(self, self.admin)

  self.res.status = 200
  return json_response(self, response)
end

function _M.destroy(self)
  assert(self.admin:authorized_delete())

  return { status = 204, layout = false }
end

function _M.admin_params(self)
  local params = {}
  if self.params and type(self.params["admin"]) == "table" then
    local input = self.params["admin"]
    local is_admin_manage = self.current_admin and self.current_admin:allows_permission("admin_manage")

    if is_admin_manage then
      -- Admin managers can update all fields.
      params = dbify_json_nulls({
        username = input["username"],
        password = input["password"],
        password_confirmation = input["password_confirmation"],
        current_password = input["current_password"],
        email = input["email"],
        name = input["name"],
        notes = input["notes"],
        superuser = input["superuser"],
        group_ids = input["group_ids"],
      })

      -- Password can only be changed when editing own profile.
      if not self.admin or not self.current_admin or self.admin.id ~= self.current_admin.id then
        params["password"] = nil
        params["password_confirmation"] = nil
        params["current_password"] = nil
      end
    else
      -- Non-admin-managers can only update their own password. Restricting to
      -- only password fields prevents privilege escalation (e.g., self-granting
      -- superuser or different group memberships).
      local is_own_profile = self.admin and self.current_admin and self.admin.id == self.current_admin.id
      if is_own_profile then
        params = dbify_json_nulls({
          password = input["password"],
          password_confirmation = input["password_confirmation"],
          current_password = input["current_password"],
        })
      end
    end
  end

  return params
end

return function(app)
  app:match("/api-umbrella/v1/admins/:id(.:format)", respond_to({
    before = require_admin(function(self)
      local ok = validation_ext.string.uuid(self.params["id"])
      if ok then
        self.admin = Admin:find(self.params["id"])
      end
      if not self.admin then
        return self.app.handle_404(self)
      end
    end),
    GET = capture_errors_json_full(_M.show),
    POST = csrf_validate_token_or_admin_token_filter(capture_errors_json_full(wrapped_json_params(_M.update, "admin"))),
    PUT = csrf_validate_token_or_admin_token_filter(capture_errors_json_full(wrapped_json_params(_M.update, "admin"))),
    DELETE = csrf_validate_token_or_admin_token_filter(capture_errors_json_full(_M.destroy)),
  }))

  app:match("/api-umbrella/v1/admins(.:format)", respond_to({
    before = require_admin(),
    GET = capture_errors_json_full(_M.index),
    POST = csrf_validate_token_or_admin_token_filter(capture_errors_json_full(wrapped_json_params(_M.create, "admin"))),
  }))
end

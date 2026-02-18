local build_url = require "api-umbrella.utils.build_url"
local db = require "lapis.db"

return function(self, admin, provider)
  assert(admin)
  assert(provider)

  local admin_id = assert(admin.id)
  local admin_username = assert(admin.username)
  local ip = assert(ngx.var.remote_addr)

  db.query("START TRANSACTION")
  db.query("SET LOCAL audit.application_user_id = ?", admin_id)
  db.query("SET LOCAL audit.application_user_name = ?", admin_username)
  db.query("UPDATE admins SET last_sign_in_at = current_sign_in_at, last_sign_in_ip = current_sign_in_ip, last_sign_in_provider = current_sign_in_provider WHERE id = ?", admin_id)
  db.query("UPDATE admins SET sign_in_count = sign_in_count + 1, current_sign_in_at = now(), current_sign_in_ip = ?, current_sign_in_provider = ? WHERE id = ?", ip, provider, admin_id)
  db.query("COMMIT")

  self:init_session_db()
  self.session_db:open()
  self.session_db:set("admin_id", admin_id)
  self.session_db:set("sign_in_provider", provider)
  self.session_db:save()

  return build_url("/admin/#/login")
end

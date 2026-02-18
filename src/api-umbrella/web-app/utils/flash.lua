local is_empty = require "api-umbrella.utils.is_empty"

local _M = {}

function _M.now(self, flash_type, message, options)
  local data = options or {}
  data["message"] = message

  self.flash[flash_type] = data
end

function _M.session(self, flash_type, message, options)
  local data = options or {}
  data["message"] = message

  self:init_session_cookie()
  self.session_cookie:open()
  local flash_data = self.session_cookie:get("flash")
  if not flash_data then
    flash_data = {}
  end
  flash_data[flash_type] = data
  self.session_cookie:set("flash", flash_data)
  self.session_cookie:save()
end

function _M.setup(self)
  self.flash = {}

  self.restore_flashes = function()
    self:init_session_cookie()
    local ok, open_err = self.session_cookie:open()
    if not ok and open_err and open_err ~= "missing session cookie" then
      ngx.log(ngx.ERR, "session open error: ", open_err)
    end

    local flash_data = self.session_cookie:get("flash")
    if not is_empty(flash_data) then
      for flash_type, data in pairs(flash_data) do
        _M.now(self, flash_type, data["message"], data)
      end

      self.session_cookie:set("flash", nil)
      self.session_cookie:save()
    end

    return self.flash
  end
end

return _M

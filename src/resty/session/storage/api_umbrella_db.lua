local db = require "lapis.db"
local encode_bytea = require("pgmoon").Postgres.encode_bytea

local _M = {}
_M.__index = _M

function _M.new(session)
  local self = {
    encode = session.encoder.encode,
    decode = session.encoder.decode,
  }

  return setmetatable(self, _M)
end

function _M.open(_, id_encoded)
  local data
  local res = db.query("SELECT data_encrypted FROM sessions WHERE id_hash = ? AND expires_at >= now()", id_encoded)
  if res and res[1] and res[1]["data_encrypted"] then
    data = res[1]["data_encrypted"]
  end

  return data
end

function _M.start()
  return true
end

function _M:save(id_encoded, ttl, data)
  local id = self.decode(id_encoded)
  local iv = string.sub(id, 1, 12)

  db.query("INSERT INTO sessions(id_hash, expires_at, data_encrypted, data_encrypted_iv) VALUES(?, now() + interval ?, ?, ?) ON CONFLICT (id_hash) DO UPDATE SET expires_at = EXCLUDED.expires_at, data_encrypted = EXCLUDED.data_encrypted, data_encrypted_iv = EXCLUDED.data_encrypted_iv", id_encoded, ttl .. " seconds", db.raw(encode_bytea(nil, data)), iv)
  return true
end

function _M.close()
  return true
end

function _M.destroy(_, id_encoded)
  db.query("DELETE FROM sessions WHERE id_hash = ?", id_encoded)
end

function _M.ttl(_, id_encoded, ttl)
  db.query("UPDATE sessions SET expires_at = now() + interval ? WHERE id_hash = ?", ttl .. " seconds", id_encoded)
  return true
end

return _M

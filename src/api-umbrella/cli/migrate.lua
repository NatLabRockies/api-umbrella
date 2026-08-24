local config = require("api-umbrella.utils.load_config")()
local setenv = require("posix.stdlib").setenv

-- Override the default config details that Lapis will use in src/config.lua
-- and src/migrations.lua to connect to the database.
local migrate_username = os.getenv("DB_USERNAME") or config["postgresql"]["migrations"]["username"]
local migrate_password = os.getenv("DB_PASSWORD") or config["postgresql"]["migrations"]["password"]
config["postgresql"]["username"] = migrate_username
config["postgresql"]["password"] = migrate_password
config["postgresql"]["timeout"] = 24 * 60 * 60 * 1000

local db = require("lapis.db")
local migrations = require("lapis.db.migrations")
local path_join = require "api-umbrella.utils.path_join"
local pg_utils = require "api-umbrella.utils.pg_utils"
local pl_utils = require "pl.utils"
local shell_blocking = require("shell-games")
local split = require("ngx.re").split
local startswith = require("pl.stringx").startswith

local readfile = pl_utils.readfile
local writefile = pl_utils.writefile

return function()
  db.query("SET search_path = api_umbrella, public")
  migrations.run_migrations(require("migrations"))

  pg_utils.db_config["user"] = migrate_username
  pg_utils.db_config["password"] = migrate_password

  local grants_sql_path = path_join(os.getenv("API_UMBRELLA_SRC_ROOT"), "db/grants.sql")
  local grants_sql = readfile(grants_sql_path, true)
  pg_utils.query(grants_sql, nil, { verbose = true, fatal = true })

  -- In development, dump the db/schema.sql file after migrations.
  if config["app_env"] == "development" then
    setenv("PGHOST", config["postgresql"]["host"])
    setenv("PGPORT", config["postgresql"]["port"])
    setenv("PGDATABASE", config["postgresql"]["database"])
    setenv("PGUSER", migrate_username)
    setenv("PGPASSWORD", migrate_password)
    local schema_path = path_join(os.getenv("API_UMBRELLA_SRC_ROOT"), "db/schema.sql")
    local _, err = shell_blocking.run({
      "pg_dump",
      "--schema-only",
      "--no-privileges",
      "--no-owner",
      "--file", schema_path,
    })
    if err then
      print(err)
      os.exit(1)
    end

    local schema_sql = readfile(schema_path, true)
    local lines, split_err = split(schema_sql, "\n")
    if split_err then
      print(split_err)
      os.exit(1)
    end

    local clean_lines = {}
    local removing_comments = true
    for _, line in ipairs(lines) do
      if (not removing_comments or (line ~= "" and not startswith(line, "--"))) and not startswith(line, "\\restrict") and not startswith(line, "\\unrestrict") then
        if startswith(line, "COMMENT ON EXTENSION") then
          line = "-- " .. line
        end

        table.insert(clean_lines, line)
        removing_comments = false
      end
    end


    local migrations_result, migrations_err = pg_utils.query("SELECT name FROM api_umbrella.lapis_migrations ORDER BY name")
    if migrations_err then
      print(migrations_err)
      os.exit(1)
    end

    local migrations_sql = {}
    for _, migration in ipairs(migrations_result) do
      table.insert(migrations_sql, "INSERT INTO api_umbrella.lapis_migrations (name) VALUES (" .. pg_utils.escape_literal(migration["name"]) .. ");")
    end

    schema_sql = table.concat(clean_lines, "\n") .. "\n\n" .. table.concat(migrations_sql, "\n") .. "\n"
    writefile(schema_path, schema_sql, true)
  end
end

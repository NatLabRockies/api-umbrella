local db = require("lapis.db")
local json_encode = require "api-umbrella.utils.json_encode"
local path_join = require "api-umbrella.utils.path_join"
local readfile = require("pl.utils").readfile

local grants_sql_path = path_join(os.getenv("API_UMBRELLA_SRC_ROOT"), "db/grants.sql")
local grants_sql = readfile(grants_sql_path, true)

return {
  [1498350289] = function()
    db.query("START TRANSACTION")
    db.query("CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public")

    local audit_sql_path = path_join(os.getenv("API_UMBRELLA_SRC_ROOT"), "db/pg-audit-json--1.0.1.sql")
    local audit_sql = readfile(audit_sql_path, true)
    audit_sql = ngx.re.sub(audit_sql, [[^(\\echo Use)]], "-- $1", "m")
    audit_sql = ngx.re.sub(audit_sql, [[^(SELECT pg_catalog.pg_extension_config_dump)]], "-- $1", "m")
    db.query("SET search_path = public")
    db.query(audit_sql)
    db.query("CREATE INDEX ON audit.log(schema_name, table_name)")
    db.query("CREATE INDEX ON audit.log(application_user_name)")
    db.query("CREATE INDEX ON audit.log((row_data->>'id'))")

    db.query("CREATE SCHEMA IF NOT EXISTS api_umbrella")
    db.query("SET search_path = api_umbrella, public")

    db.query([[
      CREATE OR REPLACE FUNCTION current_app_user_id()
      RETURNS uuid AS $$
      BEGIN
        RETURN current_setting('audit.application_user_id')::uuid;
      END;
      $$ LANGUAGE plpgsql;
    ]])

    db.query([[
      CREATE OR REPLACE FUNCTION current_app_username()
      RETURNS varchar(255) AS $$
      BEGIN
        RETURN current_setting('audit.application_user_name');
      END;
      $$ LANGUAGE plpgsql;
    ]])

    db.query([[
      CREATE OR REPLACE FUNCTION stamp_record()
      RETURNS TRIGGER AS $$
      DECLARE
        associations jsonb;
        association jsonb;
      BEGIN
        -- Only perform stamping ON INSERT/DELETE or if the UPDATE actually
        -- changed any fields.
        --
        -- Detect changes using *<> operator which is compatible with "point"
        -- types that "DISTINCT FROM" is not:
        -- https://www.mail-archive.com/pgsql-general@postgresql.org/msg198866.html
        -- https://www.postgresql.org/docs/10/functions-comparisons.html#COMPOSITE-TYPE-COMPARISON
        IF (COALESCE(current_setting('api_umbrella.disable_stamping', true), 'off') != 'on' AND (TG_OP != 'UPDATE' OR NEW *<> OLD)) THEN
          -- Update the updated_at timestamp on associated tables (which in
          -- turn will trigger this stamp_record() on that table if the
          -- timestamp changes to take care of any userstamping).
          --
          -- This is done so that insert/updates/deletes of nested data cascade
          -- the updated stamping information to any parent records. For
          -- example, when changing rate limits for a API user:
          --
          -- 1. The insert/update/delete on rate_limits will trigger an update
          --    on the parent api_user_settings record.
          -- 2. The update on the api_user_settings record will trigger an
          --    update on the parent api_user record.
          -- 3. The update on the api_user record will trigger its own update
          --    triggers (which in the case of api_users will result in the
          --    "version" being incremented).
          --
          -- This is primarily for the nested relationship data in api_users
          -- and api_backends, since it keeps the top-level record's timestamps
          -- updated whenever any child record is updated. This is useful for
          -- display purposes (so the updated timestamp of the top-level record
          -- accurately takes into account child record modifications). More
          -- importantly, this is necessary for some of our polling mechanisms
          -- which rely on record timestamps or version increments on the
          -- top-level records to detect any changes and invalidate caches (for
          -- example, detecting when api_users are changed to clear the proxy
          -- cache).
          --
          -- Note: We don't try to automatically detect all associations based
          -- on foreign keys, since that can lead to unnecessary updates (eg,
          -- when updating "api_users_roles" it only really makes sense to
          -- cascade the update time to the user, but not the roles table),
          -- which can also lead to deadlocks under higher concurrency (seen
          -- mainly in our test environment).
          IF TG_ARGV[0] IS NOT NULL THEN
            associations = TG_ARGV[0]::jsonb;
            FOR association IN SELECT * FROM jsonb_array_elements(associations)
            LOOP
              EXECUTE format('UPDATE %I SET updated_at = transaction_timestamp() WHERE %I = ($1).%s', association->>'table_name', association->>'primary_key', association->>'foreign_key') USING (CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END);
            END LOOP;
          END IF;

          -- Set the created/updated timestamp and userstamp columns on INSERT
          -- or UPDATE.
          CASE TG_OP
          WHEN 'INSERT' THEN
            -- Use COALESCE to allow for overriding these values with custom
            -- settings on create. The app shouldn't ever set these itself,
            -- this is primarily for the test environment, where it's sometimes
            -- useful to be able to create records with older timestamps.
            NEW.created_at := COALESCE(NEW.created_at, transaction_timestamp());
            NEW.created_by_id := COALESCE(NEW.created_by_id, current_app_user_id());
            NEW.created_by_username := COALESCE(NEW.created_by_username, current_app_username());
            NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);
            NEW.updated_by_id := COALESCE(NEW.updated_by_id, NEW.created_by_id);
            NEW.updated_by_username := COALESCE(NEW.updated_by_username, NEW.created_by_username);
          WHEN 'UPDATE' THEN
            NEW.updated_at := transaction_timestamp();
            NEW.updated_by_id := current_app_user_id();
            NEW.updated_by_username := current_app_username();
          WHEN 'DELETE' THEN
            -- Do nothing on deletes.
          END CASE;
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        ELSE
          RETURN NEW;
        END IF;
      END;
      $$ LANGUAGE plpgsql;
    ]])

    db.query([[
      CREATE OR REPLACE FUNCTION update_timestamp()
      RETURNS TRIGGER AS $$
      BEGIN
        -- Detect changes using *<> operator which is compatible with "point"
        -- types that "DISTINCT FROM" is not:
        -- https://www.mail-archive.com/pgsql-general@postgresql.org/msg198866.html
        -- https://www.postgresql.org/docs/10/functions-comparisons.html#COMPOSITE-TYPE-COMPARISON
        IF NEW *<> OLD THEN
          NEW.updated_at := transaction_timestamp();
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])


    db.query([[
      CREATE OR REPLACE FUNCTION next_api_backend_sort_order()
      RETURNS int AS $$
      BEGIN
        RETURN (SELECT COALESCE(MAX(sort_order), 0) + 10000 FROM api_backends);
      END;
      $$ LANGUAGE plpgsql;
    ]])

    db.query([[
      CREATE TABLE admins(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        username varchar(255) NOT NULL,
        email varchar(255),
        name varchar(255),
        notes text,
        superuser boolean NOT NULL DEFAULT FALSE,
        authentication_token_hash varchar(64) NOT NULL,
        authentication_token_encrypted varchar(76) NOT NULL,
        authentication_token_encrypted_iv varchar(12) NOT NULL,
        current_sign_in_provider varchar(100),
        last_sign_in_provider varchar(100),
        password_hash varchar(60),
        reset_password_token_hash varchar(64),
        reset_password_sent_at timestamp with time zone,
        remember_created_at timestamp with time zone,
        sign_in_count integer NOT NULL DEFAULT 0,
        current_sign_in_at timestamp with time zone,
        last_sign_in_at timestamp with time zone,
        current_sign_in_ip inet,
        last_sign_in_ip inet,
        failed_attempts integer NOT NULL DEFAULT 0,
        unlock_token_hash varchar(64),
        locked_at timestamp with time zone,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON admins(username)")
    db.query("CREATE UNIQUE INDEX ON admins(authentication_token_hash)")
    db.query("CREATE UNIQUE INDEX ON admins(reset_password_token_hash)")
    db.query("CREATE UNIQUE INDEX ON admins(unlock_token_hash)")
    db.query("CREATE TRIGGER admins_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON admins FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('admins')")

    db.query([[
      CREATE TABLE admin_permissions(
        id varchar(50) PRIMARY KEY,
        name varchar(255) NOT NULL,
        display_order smallint NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE INDEX ON admin_permissions(display_order)")
    db.query("CREATE TRIGGER admin_permissions_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON admin_permissions FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('admin_permissions')")

    db.query([[
      CREATE TABLE api_scopes(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name varchar(255) NOT NULL,
        host varchar(255) NOT NULL,
        path_prefix varchar(255) NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_scopes(host, path_prefix)")
    db.query("CREATE TRIGGER api_scopes_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_scopes FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('api_scopes')")

    db.query([[
      CREATE TABLE admin_groups(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name varchar(255) NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON admin_groups(name)")
    db.query("CREATE TRIGGER admin_groups_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON admin_groups FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('admin_groups')")

    db.query([[
      CREATE TABLE admin_groups_admin_permissions(
        admin_group_id uuid REFERENCES admin_groups ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        admin_permission_id varchar(50) REFERENCES admin_permissions ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL,
        PRIMARY KEY(admin_group_id, admin_permission_id)
      )
    ]])
    db.query("CREATE TRIGGER admin_groups_admin_permissions_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON admin_groups_admin_permissions FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "admin_groups",
        primary_key = "id",
        foreign_key = "admin_group_id",
      },
    }))
    db.query("SELECT audit.audit_table('admin_groups_admin_permissions')")

    db.query([[
      CREATE TABLE admin_groups_admins(
        admin_group_id uuid REFERENCES admin_groups ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        admin_id uuid REFERENCES admins ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL,
        PRIMARY KEY(admin_group_id, admin_id)
      )
    ]])
    db.query("CREATE TRIGGER admin_groups_admins_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON admin_groups_admins FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "admins",
        primary_key = "id",
        foreign_key = "admin_id",
      },
    }))
    db.query("SELECT audit.audit_table('admin_groups_admins')")

    db.query([[
      CREATE TABLE admin_groups_api_scopes(
        admin_group_id uuid REFERENCES admin_groups ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        api_scope_id uuid REFERENCES api_scopes ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL,
        PRIMARY KEY(admin_group_id, api_scope_id)
      )
    ]])
    db.query("CREATE TRIGGER admin_groups_api_scopes_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON admin_groups_api_scopes FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "admin_groups",
        primary_key = "id",
        foreign_key = "admin_group_id",
      },
    }))
    db.query("SELECT audit.audit_table('admin_groups_api_scopes')")

    db.query([[
      CREATE TABLE api_roles(
        id varchar(255) PRIMARY KEY,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE TRIGGER api_roles_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_roles FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('api_roles')")

    db.query([[
      CREATE TABLE api_backends(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name varchar(255) NOT NULL,
        sort_order int NOT NULL DEFAULT next_api_backend_sort_order(),
        backend_protocol varchar(5) NOT NULL CHECK(backend_protocol IN('http', 'https')),
        frontend_host varchar(255) NOT NULL,
        backend_host varchar(255),
        balance_algorithm varchar(11) NOT NULL CHECK(balance_algorithm IN('round_robin', 'least_conn', 'ip_hash')),
        keepalive_connections smallint,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE INDEX ON api_backends(sort_order)")
    db.query("CREATE TRIGGER api_backends_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backends FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('api_backends')")

    db.query([[
      CREATE TABLE api_backend_rewrites(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_backend_id uuid NOT NULL REFERENCES api_backends ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        matcher_type varchar(5) NOT NULL CHECK(matcher_type IN('route', 'regex')),
        http_method varchar(7) NOT NULL CHECK(http_method IN('any', 'GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'TRACE', 'OPTIONS', 'CONNECT', 'PATCH')),
        frontend_matcher varchar(255) NOT NULL,
        backend_replacement varchar(255) NOT NULL,
        sort_order int NOT NULL DEFAULT 0,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_backend_rewrites(api_backend_id, matcher_type, http_method, frontend_matcher)")
    db.query("CREATE UNIQUE INDEX ON api_backend_rewrites(api_backend_id, sort_order)")
    db.query("CREATE TRIGGER api_backend_rewrites_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backend_rewrites FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backends",
        primary_key = "id",
        foreign_key = "api_backend_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_backend_rewrites')")

    db.query([[
      CREATE TABLE api_backend_servers(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_backend_id uuid NOT NULL REFERENCES api_backends ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        host varchar(255) NOT NULL,
        port int NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_backend_servers(api_backend_id, host, port)")
    db.query("CREATE TRIGGER api_backend_servers_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backend_servers FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backends",
        primary_key = "id",
        foreign_key = "api_backend_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_backend_servers')")

    db.query([[
      CREATE TABLE api_backend_sub_url_settings(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_backend_id uuid NOT NULL REFERENCES api_backends ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        http_method varchar(7) NOT NULL CHECK(http_method IN('any', 'GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'TRACE', 'OPTIONS', 'CONNECT', 'PATCH')),
        regex varchar(255) NOT NULL,
        sort_order int NOT NULL DEFAULT 0,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_backend_sub_url_settings(api_backend_id, http_method, regex)")
    db.query("CREATE UNIQUE INDEX ON api_backend_sub_url_settings(api_backend_id, sort_order)")
    db.query("CREATE TRIGGER api_backend_sub_url_settings_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backend_sub_url_settings FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backends",
        primary_key = "id",
        foreign_key = "api_backend_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_backend_sub_url_settings')")

    db.query([[
      CREATE TABLE api_backend_url_matches(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_backend_id uuid NOT NULL REFERENCES api_backends ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        frontend_prefix varchar(255) NOT NULL,
        backend_prefix varchar(255) NOT NULL,
        sort_order int NOT NULL DEFAULT 0,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_backend_url_matches(api_backend_id, frontend_prefix)")
    db.query("CREATE UNIQUE INDEX ON api_backend_url_matches(api_backend_id, sort_order)")
    db.query("CREATE TRIGGER api_backend_url_matches_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backend_url_matches FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backends",
        primary_key = "id",
        foreign_key = "api_backend_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_backend_url_matches')")

    db.query([[
      CREATE TABLE api_backend_settings(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_backend_id uuid REFERENCES api_backends ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        api_backend_sub_url_settings_id uuid REFERENCES api_backend_sub_url_settings ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        append_query_string varchar(255),
        http_basic_auth varchar(255),
        require_https varchar(23) CHECK(require_https IN('required_return_error', 'transition_return_error', 'optional')),
        require_https_transition_start_at timestamp with time zone,
        redirect_https boolean NOT NULL DEFAULT FALSE,
        disable_api_key boolean,
        api_key_verification_level varchar(16) CHECK(api_key_verification_level IN('none', 'transition_email', 'required_email')),
        api_key_verification_transition_start_at timestamp with time zone,
        required_roles_override boolean NOT NULL DEFAULT FALSE,
        pass_api_key_header boolean NOT NULL DEFAULT FALSE,
        pass_api_key_query_param boolean NOT NULL DEFAULT FALSE,
        rate_limit_bucket_name varchar(255),
        rate_limit_mode varchar(9) CHECK(rate_limit_mode IN('unlimited', 'custom')),
        anonymous_rate_limit_behavior varchar(11) CHECK(anonymous_rate_limit_behavior IN('ip_fallback', 'ip_only')),
        authenticated_rate_limit_behavior varchar(12) CHECK(authenticated_rate_limit_behavior IN('all', 'api_key_only')),
        error_templates jsonb,
        error_data jsonb,
        allowed_ips inet ARRAY,
        allowed_referers varchar(500) ARRAY,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL,
        CONSTRAINT parent_id_not_null CHECK((api_backend_id IS NOT NULL AND api_backend_sub_url_settings_id IS NULL) OR (api_backend_id IS NULL AND api_backend_sub_url_settings_id IS NOT NULL))
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_backend_settings(api_backend_id)")
    db.query("CREATE UNIQUE INDEX ON api_backend_settings(api_backend_sub_url_settings_id)")
    db.query("CREATE TRIGGER api_backend_settings_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backend_settings FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backends",
        primary_key = "id",
        foreign_key = "api_backend_id",
      },
      {
        table_name = "api_backend_sub_url_settings",
        primary_key = "id",
        foreign_key = "api_backend_sub_url_settings_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_backend_settings')")

    db.query([[
      CREATE TABLE api_backend_settings_required_roles(
        api_backend_settings_id uuid NOT NULL REFERENCES api_backend_settings ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        api_role_id varchar(255) NOT NULL REFERENCES api_roles ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL,
        PRIMARY KEY(api_backend_settings_id, api_role_id)
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_backend_settings_required_roles(api_backend_settings_id, api_role_id)")
    db.query("CREATE TRIGGER api_backend_settings_required_roles_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backend_settings_required_roles FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backend_settings",
        primary_key = "id",
        foreign_key = "api_backend_settings_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_backend_settings_required_roles')")

    db.query([[
      CREATE TABLE api_backend_http_headers(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_backend_settings_id uuid NOT NULL REFERENCES api_backend_settings ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        header_type varchar(17) NOT NULL CHECK(header_type IN('request', 'response_default', 'response_override')),
        sort_order int NOT NULL,
        key varchar(255) NOT NULL,
        value varchar(255),
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_backend_http_headers(api_backend_settings_id, header_type, sort_order)")
    db.query("CREATE TRIGGER api_backend_http_headers_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_backend_http_headers FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backend_settings",
        primary_key = "id",
        foreign_key = "api_backend_settings_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_backend_http_headers')")

    db.query([[
      CREATE TABLE api_users(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        version bigint NOT NULL,
        api_key_hash varchar(64) NOT NULL,
        api_key_encrypted varchar(76) NOT NULL,
        api_key_encrypted_iv varchar(12) NOT NULL,
        api_key_prefix varchar(16) NOT NULL,
        email varchar(255) NOT NULL,
        email_verified boolean NOT NULL DEFAULT FALSE,
        first_name varchar(80),
        last_name varchar(80),
        use_description varchar(2000),
        website varchar(255),
        metadata jsonb,
        registration_ip inet,
        registration_source varchar(255),
        registration_user_agent varchar(1000),
        registration_referer varchar(1000),
        registration_origin varchar(1000),
        throttle_by_ip boolean NOT NULL DEFAULT FALSE,
        disabled_at timestamp with time zone,
        imported boolean NOT NULL DEFAULT FALSE,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_users(version)")
    db.query("CREATE UNIQUE INDEX ON api_users(api_key_hash)")
    db.query("CREATE UNIQUE INDEX ON api_users(api_key_prefix)")
    -- Use the full negative and positive bigint range for this sequence.
    --
    -- For the minimum value, we actually use 1 plus the bigint minimum so we
    -- can more easily perform "last_value - 1" math in some of our queries
    -- without exceeding the bigint range.
    db.query("CREATE SEQUENCE api_users_version_seq MINVALUE -9223372036854775807 MAXVALUE 9223372036854775807")
    db.query([[
      CREATE OR REPLACE FUNCTION api_users_increment_version()
      RETURNS TRIGGER AS $$
      BEGIN
        -- Only increment the version on INSERT or if the UPDATE actually
        -- changed any fields.
        --
        -- Detect changes using *<> operator which is compatible with "point"
        -- types that "DISTINCT FROM" is not:
        -- https://www.mail-archive.com/pgsql-general@postgresql.org/msg198866.html
        -- https://www.postgresql.org/docs/10/functions-comparisons.html#COMPOSITE-TYPE-COMPARISON
        IF TG_OP != 'UPDATE' OR NEW *<> OLD THEN
          NEW.version := nextval('api_users_version_seq');
        END IF;

        return NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])
    db.query("CREATE TRIGGER api_users_increment_version_trigger BEFORE INSERT OR UPDATE ON api_users FOR EACH ROW EXECUTE PROCEDURE api_users_increment_version()")
    db.query("CREATE TRIGGER api_users_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_users FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('api_users')")

    db.query([[
      CREATE TABLE api_users_roles(
        api_user_id uuid NOT NULL REFERENCES api_users ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        api_role_id varchar(255) NOT NULL REFERENCES api_roles ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL,
        PRIMARY KEY(api_user_id, api_role_id)
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON api_users_roles(api_user_id, api_role_id)")
    db.query("CREATE TRIGGER api_users_roles_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_users_roles FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_users",
        primary_key = "id",
        foreign_key = "api_user_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_users_roles')")

    db.query([[
      CREATE TABLE api_user_settings(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_user_id uuid NOT NULL REFERENCES api_users ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        rate_limit_mode varchar(9) CHECK(rate_limit_mode IN('unlimited', 'custom')),
        allowed_ips inet ARRAY,
        allowed_referers varchar(500) ARRAY,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE TRIGGER api_user_settings_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON api_user_settings FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_users",
        primary_key = "id",
        foreign_key = "api_user_id",
      },
    }))
    db.query("SELECT audit.audit_table('api_user_settings')")

    db.query([[
      CREATE TABLE published_config(
        id bigserial PRIMARY KEY,
        config jsonb NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE TRIGGER published_config_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON published_config FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('published_config')")

    db.query([[
      CREATE TABLE rate_limits(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        api_backend_settings_id uuid REFERENCES api_backend_settings ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        api_user_settings_id uuid REFERENCES api_user_settings ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
        duration bigint NOT NULL,
        accuracy bigint NOT NULL,
        limit_by varchar(7) NOT NULL CHECK(limit_by IN('ip', 'api_key')),
        limit_to bigint NOT NULL,
        distributed boolean NOT NULL DEFAULT FALSE,
        response_headers boolean NOT NULL DEFAULT FALSE,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL,
        CONSTRAINT settings_id_not_null CHECK((api_backend_settings_id IS NOT NULL AND api_user_settings_id IS NULL) OR (api_backend_settings_id IS NULL AND api_user_settings_id IS NOT NULL))
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON rate_limits(api_backend_settings_id, api_user_settings_id, limit_by, duration)")
    db.query("CREATE TRIGGER rate_limits_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON rate_limits FOR EACH ROW EXECUTE PROCEDURE stamp_record(?)", json_encode({
      {
        table_name = "api_backend_settings",
        primary_key = "id",
        foreign_key = "api_backend_settings_id",
      },
      {
        table_name = "api_user_settings",
        primary_key = "id",
        foreign_key = "api_user_settings_id",
      },
    }))
    db.query("SELECT audit.audit_table('rate_limits')")

    db.query([[
      CREATE TABLE website_backends(
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        frontend_host varchar(255) NOT NULL,
        backend_protocol varchar(5) NOT NULL CHECK(backend_protocol IN('http', 'https')),
        server_host varchar(255) NOT NULL,
        server_port int NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_id uuid NOT NULL,
        created_by_username varchar(255) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_id uuid NOT NULL,
        updated_by_username varchar(255) NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON website_backends(frontend_host)")
    db.query("CREATE TRIGGER website_backends_stamp_record BEFORE INSERT OR UPDATE OR DELETE ON website_backends FOR EACH ROW EXECUTE PROCEDURE stamp_record()")
    db.query("SELECT audit.audit_table('website_backends')")

    db.query([[
      CREATE TABLE sessions(
        id_hash varchar(64) PRIMARY KEY,
        data_encrypted bytea NOT NULL,
        data_encrypted_iv varchar(12) NOT NULL,
        expires_at timestamp with time zone NOT NULL,
        created_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp(),
        updated_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp()
      )
    ]])
    db.query("CREATE INDEX ON sessions(expires_at)")
    db.query("CREATE TRIGGER sessions_stamp_record BEFORE UPDATE ON sessions FOR EACH ROW EXECUTE PROCEDURE update_timestamp()")

    db.query([[
      CREATE TABLE analytics_cities(
        id serial PRIMARY KEY,
        country varchar(2) NOT NULL,
        region varchar(2),
        city varchar(200),
        location point NOT NULL,
        created_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp(),
        updated_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp()
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON analytics_cities(country, region, city)")
    db.query("CREATE TRIGGER analytics_cities_stamp_record BEFORE UPDATE ON analytics_cities FOR EACH ROW EXECUTE PROCEDURE update_timestamp()")

    db.query([[
      CREATE TABLE distributed_rate_limit_counters(
        id varchar(500) PRIMARY KEY,
        version bigint NOT NULL,
        value bigint NOT NULL,
        expires_at timestamp with time zone NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON distributed_rate_limit_counters(version)")
    db.query("CREATE INDEX ON distributed_rate_limit_counters(expires_at)")
    -- Use the full negative and positive bigint range for this sequence.
    --
    -- For the minimum value, we actually use 1 plus the bigint minimum so we
    -- can more easily perform "last_value - 1" math in some of our queries
    -- without exceeding the bigint range.
    db.query("CREATE SEQUENCE distributed_rate_limit_counters_version_seq MINVALUE -9223372036854775807 MAXVALUE 9223372036854775807 CYCLE")
    db.query([[
      CREATE OR REPLACE FUNCTION distributed_rate_limit_counters_increment_version()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.version := nextval('distributed_rate_limit_counters_version_seq');
        return NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])
    db.query("CREATE TRIGGER distributed_rate_limit_counters_increment_version_trigger BEFORE INSERT OR UPDATE ON distributed_rate_limit_counters FOR EACH ROW EXECUTE PROCEDURE distributed_rate_limit_counters_increment_version()")

    db.query([[
      CREATE TABLE cache(
        id varchar(255) PRIMARY KEY,
        data bytea NOT NULL,
        expires_at timestamp with time zone,
        created_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp(),
        updated_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp()
      )
    ]])
    db.query("CREATE INDEX ON cache(expires_at)")
    db.query("CREATE TRIGGER cache_stamp_record BEFORE UPDATE ON cache FOR EACH ROW EXECUTE PROCEDURE update_timestamp()")

    db.query([[
      CREATE VIEW api_users_flattened AS
        SELECT u.id,
          u.version,
          u.api_key_hash,
          u.api_key_encrypted,
          u.api_key_encrypted_iv,
          u.email,
          u.email_verified,
          u.registration_source,
          u.throttle_by_ip,
          extract(epoch from u.disabled_at) AS disabled_at,
          extract(epoch from u.created_at) AS created_at,
          json_build_object(
            'allowed_ips', s.allowed_ips,
            'allowed_referers', s.allowed_referers,
            'rate_limit_mode', s.rate_limit_mode,
            'rate_limits', (
              SELECT json_agg(r2.*)
              FROM (
                SELECT
                  r.duration,
                  r.accuracy,
                  r.limit_by,
                  r.limit_to,
                  r.distributed,
                  r.response_headers
                FROM rate_limits AS r
                WHERE r.api_user_settings_id = s.id
              ) AS r2
            )
          ) AS settings,
          ARRAY(SELECT ar.api_role_id FROM api_users_roles AS ar WHERE ar.api_user_id = u.id) AS roles
        FROM api_users AS u
          LEFT JOIN api_user_settings AS s ON u.id = s.api_user_id
    ]])

    db.query([[
      CREATE TABLE audit.legacy_log(
        id bigserial PRIMARY KEY,
        version bigint NOT NULL,
        original_class varchar(255) NOT NULL,
        original_class_id varchar(36) NOT NULL,
        altered_attributes jsonb NOT NULL,
        full_attributes jsonb NOT NULL,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL
      )
    ]])

    db.query("COMMIT")
  end,

  [1554823736] = function()
    db.query("ALTER TABLE api_umbrella.api_backends ADD COLUMN organization_name varchar(255)")
    db.query("ALTER TABLE api_umbrella.api_backends ADD COLUMN status_description varchar(255)")
  end,

  [1560722058] = function()
    db.query([[
      CREATE TABLE analytics_cache(
        id varchar(64) PRIMARY KEY,
        id_data jsonb NOT NULL,
        data jsonb NOT NULL,
        expires_at timestamp with time zone,
        created_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp(),
        updated_at timestamp with time zone NOT NULL DEFAULT transaction_timestamp()
      )
    ]])
    db.query("CREATE INDEX ON analytics_cache(expires_at)")
    db.query("CREATE TRIGGER analytics_cache_stamp_record BEFORE UPDATE ON analytics_cache FOR EACH ROW EXECUTE PROCEDURE update_timestamp()")
  end,

  [1560888068] = function()
    db.query([[
      CREATE AGGREGATE array_accum (anyarray) (
        sfunc = array_cat,
        stype = anyarray,
        initcond = '{}'
      )
    ]])
    -- Add an extra column to store the unique user IDs in a fashion more
    -- optimized for querying. But since this strategy only works if each row
    -- represents a single date bucket, add extra constraints to ensure we
    -- don't accidentally mess up this assumption in the future.
    db.query("ALTER TABLE analytics_cache ADD COLUMN unique_user_ids uuid[]")
    db.query("ALTER TABLE analytics_cache ADD CONSTRAINT analytics_cache_enforce_single_date_bucket CHECK (NOT jsonb_array_length(data->'aggregations'->'hits_over_time'->'buckets') > 1)")
    db.query([[
      CREATE FUNCTION analytics_cache_extract_unique_user_ids()
      RETURNS TRIGGER AS $$
      BEGIN
        IF (jsonb_typeof(NEW.data->'aggregations'->'hits_over_time'->'buckets'->0->'unique_user_ids'->'buckets') = 'array') THEN
          NEW.unique_user_ids := (SELECT array_agg(DISTINCT bucket->>'key')::uuid[] FROM jsonb_array_elements(NEW.data->'aggregations'->'hits_over_time'->'buckets'->0->'unique_user_ids'->'buckets') AS bucket);
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])
    db.query([[
      CREATE TRIGGER analytics_cache_unique_user_ids
      BEFORE INSERT OR UPDATE OF data ON analytics_cache
      FOR EACH ROW
      EXECUTE PROCEDURE analytics_cache_extract_unique_user_ids()
    ]])
    db.query("UPDATE analytics_cache SET data = data")
  end,

  [1595106665] = function()
    local pg_encode_json = require("pgmoon.json").encode_json

    db.query("BEGIN")
    db.query("SET SESSION api_umbrella.disable_stamping = 'on'")

    local unpublish_url_matches = {}

    local res = db.query("SELECT * FROM published_config ORDER BY id DESC LIMIT 1")
    if res and res[1] then
      local apis = res[1]["config"]["apis"]

      local url_prefixes = {}
      for _, api in ipairs(apis) do
        for _, url_match in ipairs(api["url_matches"]) do
          table.insert(url_prefixes, {
            url_prefix = api["frontend_host"] .. url_match["frontend_prefix"],
            url_backend_prefix = api["backend_host"] .. url_match["backend_prefix"],
            frontend_prefix = url_match["frontend_prefix"],
            backend_prefix = url_match["backend_prefix"],
            url_match = url_match,
            api = api,
          })
        end
      end

      for index1, url_prefix1 in ipairs(url_prefixes) do
        local index1_printed = false
        for index2, url_prefix2 in ipairs(url_prefixes) do
          local url_prefix2_common_prefix = string.sub(url_prefix2["url_prefix"], 1, string.len(url_prefix1["url_prefix"]))
          local url_prefix2_with_url_prefix1_backend = url_prefix1["url_backend_prefix"] .. string.sub(url_prefix2["url_prefix"], string.len(url_prefix1["url_prefix"]) + 1)
          if index2 > index1 and url_prefix2_common_prefix == url_prefix1["url_prefix"] and (url_prefix1["api"]["id"] ~= url_prefix2["api"]["id"] or url_prefix2_with_url_prefix1_backend ~= url_prefix2["url_backend_prefix"]) then
            if not index1_printed then
              print("================================================================================")
              print("WARNING: URL matches present that will never be matched given the current ordering.")
              print("")
              print("URL that will be matched first currently:")
              print("  " .. url_prefix1["url_prefix"])
              print("    ID: " .. url_prefix1["api"]["id"])
              print("    Name: " .. url_prefix1["api"]["name"])
              print("    Sort Order: " .. url_prefix1["api"]["sort_order"])
              print("    Created At: " .. url_prefix1["api"]["created_at"])
              print("    Backend Prefix: " .. url_prefix1["url_backend_prefix"])
              print("")
              print("Other URLs that are defined, but will never be matched currently, so removing these from published config:")
              index1_printed = true
            end

            print("  - " .. url_prefix2["url_prefix"])
            print("      ID: " .. url_prefix2["api"]["id"])
            print("      Name: " .. url_prefix2["api"]["name"])
            print("      Sort Order: " .. url_prefix2["api"]["sort_order"])
            print("      Created At: " .. url_prefix2["api"]["created_at"])
            print("      Backend Prefix for this Unused Route:        " .. url_prefix2["url_backend_prefix"])
            print("      Backend Prefix for Currently Matching Route: " .. url_prefix2_with_url_prefix1_backend)

            -- Keep track of URL matches that would never be matched so we can
            -- unpublish these from the new config. This way they will still
            -- show up as diffs for admins to deal with, but this migration
            -- shouldn't affect the actual matching behavior in production.
            unpublish_url_matches[url_prefix2["api"]["id"] .. ":" .. url_prefix2["url_match"]["id"]] = true
          end
        end
      end
    end

    db.query("ALTER TABLE api_backend_url_matches DROP COLUMN sort_order")
    db.query("ALTER TABLE api_backends DROP COLUMN sort_order")

    db.query("ALTER TABLE api_backends ADD COLUMN created_order INTEGER")
    db.query("UPDATE api_backends SET created_order = t.rownum FROM (SELECT id, row_number() OVER (ORDER BY created_at) AS rownum FROM api_backends) AS t WHERE api_backends.id = t.id")
    db.query("ALTER TABLE api_backends ALTER COLUMN created_order SET NOT NULL")
    db.query("ALTER TABLE api_backends ALTER COLUMN created_order ADD GENERATED BY DEFAULT AS IDENTITY")

    db.query("ALTER TABLE website_backends ADD COLUMN created_order INTEGER")
    db.query("UPDATE website_backends SET created_order = t.rownum FROM (SELECT id, row_number() OVER (ORDER BY created_at) AS rownum FROM website_backends) AS t WHERE website_backends.id = t.id")
    db.query("ALTER TABLE website_backends ALTER COLUMN created_order SET NOT NULL")
    db.query("ALTER TABLE website_backends ALTER COLUMN created_order ADD GENERATED BY DEFAULT AS IDENTITY")

    db.query("DROP FUNCTION next_api_backend_sort_order")

    db.query([[
      CREATE OR REPLACE FUNCTION path_sort_order(text)
      RETURNS text[] AS $$
      DECLARE
        parts text[];
      BEGIN
        -- Split the path into an array of path parts, so items can be more
        -- logically grouped by the path levels.
        parts := string_to_array($1, '/');

        -- Remove empty strings in the array so that trailing slashes don't
        -- cause the item to be sorted above paths with real values after the
        -- slash. For example, this sorts the following examples in this order:
        -- "/foo/bar, /foo/, /foo". Without this, the empty string in "/foo/"'s
        -- array, would cause the following sort order: "/foo/, /foo/bar,
        -- /foo".
        parts := array_remove(parts, '');

        -- Append a NULL to the end of every array. Used in combination with
        -- "ORDER BY path_sort_order() NULLS LAST", this ensures that shorter,
        -- terminal paths always come after the more specific paths. For
        -- example, this forces "/foo/bar, /foo" (instead of "/foo" coming
        -- first).
        parts := array_append(parts, NULL);

        -- Append the length of the string to force any identical array results
        -- to sort based on the original string length in descending order
        -- (descending assuming the length of the string doesn't exceed
        -- 1,000,000 characters, which should be impossible based on other
        -- constraints). This is needed because we removed empty strings from
        -- the array above (for other sorting purposes). Without this, "/foo/"
        -- and "/foo" would have identical array results, but we want to force
        -- the longer/more specific /foo/ to sort before /foo.
        parts := array_append(parts, (1000000 - length($1))::text);

        RETURN parts;
      END;
      $$ LANGUAGE plpgsql;
    ]])

    db.query("SET SESSION api_umbrella.disable_stamping = 'off'")

    if res and res[1] then
      local config = res[1]["config"]

      table.sort(config["apis"], function(a, b)
        return a["created_at"] < b["created_at"]
      end)
      table.sort(config["website_backends"], function(a, b)
        return a["created_at"] < b["created_at"]
      end)

      for index, api in ipairs(config["apis"]) do
        api["sort_order"] = nil
        api["created_order"] = index

        -- Re-sort the published url matches with the new sort logic. Leverage
        -- the postgresql function to sort this, so the sorting logic remains
        -- consist with what postgres will do when publishing new configs.
        local sort_res = db.query("SELECT val FROM jsonb_array_elements(?) AS t(val) ORDER BY path_sort_order(val->>'frontend_prefix') NULLS LAST", db.raw(pg_encode_json(api["url_matches"])))
        api["url_matches"] = {}
        for _, row in ipairs(sort_res) do
          -- Remove any URL matches from the published config that would cause
          -- conflicts with the old sorted behavior.
          if not unpublish_url_matches[api["id"] .. ":" .. row["val"]["id"]] then
            table.insert(api["url_matches"], row["val"])
          end
        end
      end
      for index, website_backend in ipairs(config["website_backends"]) do
        website_backend["created_order"] = index
      end

      db.query("SET LOCAL audit.application_user_id = ?", "00000000-0000-0000-0000-000000000000")
      db.query("SET LOCAL audit.application_user_name = ?", "migrations")

      db.query("INSERT INTO published_config (config) VALUES (?)", db.raw(pg_encode_json(config)))
    end

    db.query("COMMIT")
  end,

  [1596759299] = function()
    db.query("BEGIN")

    db.query("DROP INDEX api_backend_servers_api_backend_id_host_port_idx")
    db.query("DROP INDEX api_backend_url_matches_api_backend_id_frontend_prefix_idx")
    db.query("DROP INDEX api_backend_http_headers_api_backend_settings_id_header_typ_idx")
    db.query("DROP INDEX api_backend_sub_url_settings_api_backend_id_sort_order_idx")
    db.query("DROP INDEX api_backend_sub_url_settings_api_backend_id_http_method_reg_idx")
    db.query("DROP INDEX api_backend_rewrites_api_backend_id_sort_order_idx")
    db.query("DROP INDEX api_backend_rewrites_api_backend_id_matcher_type_http_metho_idx")
    db.query("DROP INDEX rate_limits_api_backend_settings_id_api_user_settings_id_li_idx")

    db.query("ALTER TABLE api_backend_servers ADD CONSTRAINT api_backend_servers_host_port_uniq UNIQUE (api_backend_id, host, port) DEFERRABLE INITIALLY DEFERRED")
    db.query("ALTER TABLE api_backend_url_matches ADD CONSTRAINT api_backend_url_matches_frontend_prefix_uniq UNIQUE (api_backend_id, frontend_prefix) DEFERRABLE INITIALLY DEFERRED")
    db.query("ALTER TABLE api_backend_http_headers ADD CONSTRAINT api_backend_http_headers_sort_order_uniq UNIQUE (api_backend_settings_id, header_type, sort_order) DEFERRABLE INITIALLY DEFERRED")
    db.query("ALTER TABLE api_backend_sub_url_settings ADD CONSTRAINT api_backend_sub_url_settings_sort_order_uniq UNIQUE (api_backend_id, sort_order) DEFERRABLE INITIALLY DEFERRED")
    db.query("ALTER TABLE api_backend_sub_url_settings ADD CONSTRAINT api_backend_sub_url_settings_regex_uniq UNIQUE (api_backend_id, http_method, regex) DEFERRABLE INITIALLY DEFERRED")
    db.query("ALTER TABLE api_backend_rewrites ADD CONSTRAINT api_backend_rewrites_sort_order_uniq UNIQUE (api_backend_id, sort_order) DEFERRABLE INITIALLY DEFERRED")
    db.query("ALTER TABLE api_backend_rewrites ADD CONSTRAINT api_backend_rewrites_frontend_matcher_uniq UNIQUE (api_backend_id, matcher_type, http_method, frontend_matcher) DEFERRABLE INITIALLY DEFERRED")
    db.query("ALTER TABLE rate_limits ADD CONSTRAINT rate_limits_duration_uniq UNIQUE (api_backend_settings_id, api_user_settings_id, limit_by, duration) DEFERRABLE INITIALLY DEFERRED")

    db.query("COMMIT")
  end,

  [1635022846] = function()
    -- Done (1699559596): Drop and replace `api_users_flattened` view once we're done
    -- testing two different stacks in parallel. But for now, keep the old view
    -- as-is so we can test this new one separately.
    db.query([[
      DROP VIEW api_users_flattened;
      CREATE VIEW api_users_flattened AS
       SELECT u.id,
          u.version,
          u.api_key_hash,
          u.api_key_encrypted,
          u.api_key_encrypted_iv,
          u.email,
          u.email_verified,
          u.registration_source,
          u.throttle_by_ip,
          date_part('epoch'::text, u.disabled_at) AS disabled_at,
          date_part('epoch'::text, u.created_at) AS created_at,
          json_build_object('allowed_ips', s.allowed_ips, 'allowed_referers', s.allowed_referers, 'rate_limit_mode', s.rate_limit_mode, 'rate_limits', ( SELECT json_agg(r2.*) AS json_agg
                 FROM ( SELECT r.duration,
                          r.accuracy,
                          r.limit_by,
                          r.limit_to,
                          r.distributed,
                          r.response_headers
                         FROM api_umbrella.rate_limits r
                        WHERE (r.api_user_settings_id = s.id)) r2)) AS settings,
          ARRAY( SELECT ar.api_role_id
                 FROM api_umbrella.api_users_roles ar
                WHERE (ar.api_user_id = u.id)) AS roles
         FROM (api_umbrella.api_users u
           LEFT JOIN api_umbrella.api_user_settings s ON ((u.id = s.api_user_id)));

      CREATE VIEW api_users_flattened_temp AS
        SELECT
          u.id,
          u.api_key_prefix,
          u.api_key_hash,
          u.email,
          u.email_verified,
          u.registration_source,
          u.throttle_by_ip,
          extract(epoch from u.disabled_at)::int AS disabled_at,
          extract(epoch from u.created_at)::int AS created_at,
          jsonb_build_object(
            'allowed_ips', s.allowed_ips,
            'allowed_referers', s.allowed_referers,
            'rate_limit_mode', s.rate_limit_mode,
            'rate_limits', (
              SELECT jsonb_agg(r2.*)
              FROM (
                SELECT
                  r.duration,
                  r.accuracy,
                  r.limit_by,
                  r.limit_to,
                  r.distributed,
                  r.response_headers
                FROM rate_limits AS r
                WHERE r.api_user_settings_id = s.id
              ) AS r2
            )
          ) AS settings,
          (
            SELECT jsonb_object_agg(ar.api_role_id, true)
            FROM api_users_roles AS ar WHERE ar.api_user_id = u.id
          ) AS roles
        FROM api_users AS u
          LEFT JOIN api_user_settings AS s ON u.id = s.api_user_id
    ]])
  end,

  [1645733075] = function()
    db.query("BEGIN")

    db.query("CREATE INDEX ON api_users(created_at DESC)")

    db.query("COMMIT")
  end,

  [1647916501] = function()
    db.query("BEGIN")

    db.query("CREATE INDEX ON distributed_rate_limit_counters (version, expires_at)")

    db.query("COMMIT")
  end,

  [1651280172] = function()
    db.query("BEGIN")

    -- Done (1699559596): Drop column altogether and remove from api_users_flattened view
    -- once we're not testing the two different rate limiting approaches in
    -- parallel. But keep for now while some systems still use the accuracy
    -- approach.
    db.query("ALTER TABLE rate_limits ALTER COLUMN accuracy DROP NOT NULL")

    db.query("ALTER TABLE distributed_rate_limit_counters SET UNLOGGED")

    -- Done (1699559596): Drop this "temp" version of the table once we're done testing two
    -- different rate limit approaches in parallel. But we're keeping a
    -- separate table for testing the new rate limit implementation so there's
    -- not mixup between the different key types.
    db.query([[
      CREATE UNLOGGED TABLE distributed_rate_limit_counters_temp(
        id varchar(500) PRIMARY KEY,
        version bigint NOT NULL,
        value bigint NOT NULL,
        expires_at timestamp with time zone NOT NULL
      )
    ]])
    db.query("CREATE UNIQUE INDEX ON distributed_rate_limit_counters_temp(version)")
    db.query("CREATE INDEX ON distributed_rate_limit_counters_temp(expires_at)")
    db.query("CREATE INDEX ON distributed_rate_limit_counters_temp (version, expires_at)")
    db.query("CREATE SEQUENCE distributed_rate_limit_counters_temp_version_seq MINVALUE -9223372036854775807 MAXVALUE 9223372036854775807 CYCLE")
    db.query([[
      CREATE OR REPLACE FUNCTION distributed_rate_limit_counters_temp_increment_version()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.version := nextval('distributed_rate_limit_counters_temp_version_seq');
        return NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])
    db.query("CREATE TRIGGER distributed_rate_limit_counters_temp_increment_version_trigger BEFORE INSERT OR UPDATE ON distributed_rate_limit_counters_temp FOR EACH ROW EXECUTE PROCEDURE distributed_rate_limit_counters_temp_increment_version()")

    db.query("COMMIT")
  end,

  [1699559596] = function()
    db.query("BEGIN")

    -- Make the temp version the live version, removing the unused "accuracy"
    -- references. But still maintain the temp version for rollout purposes.
    db.query([[
      DROP VIEW api_users_flattened;
      CREATE VIEW api_users_flattened AS
        SELECT
          u.id,
          u.api_key_prefix,
          u.api_key_hash,
          u.email,
          u.email_verified,
          u.registration_source,
          u.throttle_by_ip,
          extract(epoch from u.disabled_at)::int AS disabled_at,
          extract(epoch from u.created_at)::int AS created_at,
          jsonb_build_object(
            'allowed_ips', s.allowed_ips,
            'allowed_referers', s.allowed_referers,
            'rate_limit_mode', s.rate_limit_mode,
            'rate_limits', (
              SELECT jsonb_agg(r2.*)
              FROM (
                SELECT
                  r.duration,
                  r.limit_by,
                  r.limit_to,
                  r.distributed,
                  r.response_headers
                FROM rate_limits AS r
                WHERE r.api_user_settings_id = s.id
              ) AS r2
            )
          ) AS settings,
          (
            SELECT jsonb_object_agg(ar.api_role_id, true)
            FROM api_users_roles AS ar WHERE ar.api_user_id = u.id
          ) AS roles
        FROM api_users AS u
          LEFT JOIN api_user_settings AS s ON u.id = s.api_user_id;

      DROP VIEW api_users_flattened_temp;
      CREATE VIEW api_users_flattened_temp AS
        SELECT * FROM api_users_flattened;
    ]])

    -- Drop unused column (from 1651280172)
    db.query("ALTER TABLE rate_limits DROP COLUMN accuracy")

    -- Make "temp" versions the live versions (from 1651280172)
    db.query("DROP TABLE distributed_rate_limit_counters")
    db.query("ALTER TABLE distributed_rate_limit_counters_temp RENAME TO distributed_rate_limit_counters")
    db.query("ALTER TABLE distributed_rate_limit_counters RENAME CONSTRAINT distributed_rate_limit_counters_temp_pkey TO distributed_rate_limit_counters_pkey")
    db.query("ALTER INDEX distributed_rate_limit_counters_temp_expires_at_idx RENAME TO distributed_rate_limit_counters_expires_at_idx")
    db.query("ALTER INDEX distributed_rate_limit_counters_temp_version_expires_at_idx RENAME TO distributed_rate_limit_counters_version_expires_at_idx")
    db.query("ALTER INDEX distributed_rate_limit_counters_temp_version_idx RENAME TO distributed_rate_limit_counters_version_idx")
    db.query("DROP SEQUENCE distributed_rate_limit_counters_version_seq")
    db.query("ALTER SEQUENCE distributed_rate_limit_counters_temp_version_seq RENAME TO distributed_rate_limit_counters_version_seq")
    db.query("CREATE SEQUENCE distributed_rate_limit_counters_temp_version_seq");
    db.query([[
      CREATE OR REPLACE FUNCTION distributed_rate_limit_counters_increment_version()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.version := nextval('distributed_rate_limit_counters_version_seq');
        return NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])
    db.query("DROP TRIGGER distributed_rate_limit_counters_temp_increment_version_trigger ON distributed_rate_limit_counters")
    db.query("DROP FUNCTION distributed_rate_limit_counters_temp_increment_version")
    db.query("CREATE TRIGGER distributed_rate_limit_counters_increment_version_trigger BEFORE INSERT OR UPDATE ON distributed_rate_limit_counters FOR EACH ROW EXECUTE PROCEDURE distributed_rate_limit_counters_increment_version()")

    -- Maintain a "_temp" version for compatibility with rollout.
    db.query("CREATE VIEW distributed_rate_limit_counters_temp AS SELECT * FROM distributed_rate_limit_counters")

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1699559696] = function()
    db.query("BEGIN")

    db.query("DROP VIEW distributed_rate_limit_counters_temp")
    db.query("DROP SEQUENCE distributed_rate_limit_counters_temp_version_seq")
    db.query("DROP VIEW api_users_flattened_temp")

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1699650325] = function()
    db.query("BEGIN")

    -- Store the associated role IDS directly on the api_users table to make for
    -- easier search indexing and to optimize the flattened SQL view.
    db.query("ALTER TABLE api_users ADD COLUMN cached_api_role_ids jsonb")
    db.query([[
      CREATE FUNCTION api_users_cache_api_role_ids_trigger()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        NEW.cached_api_role_ids := (SELECT jsonb_object_agg(api_role_id, true)
              FROM api_users_roles WHERE api_user_id = NEW.id);

        return NEW;
      END
      $$;
    ]])
    db.query([[
      CREATE TRIGGER api_users_cache_api_role_ids_trigger BEFORE INSERT OR UPDATE
      ON api_users
      FOR EACH ROW
      EXECUTE FUNCTION api_users_cache_api_role_ids_trigger()
    ]])
    db.query("SET LOCAL audit.application_user_id = ?", "00000000-0000-0000-0000-000000000000")
    db.query("SET LOCAL audit.application_user_name = ?", "migrations")
    db.query("UPDATE api_users SET updated_at = updated_at WHERE id IN (SELECT DISTINCT api_user_id FROM api_users_roles)")

    -- Keep the cached roles in sync when the join table is modified directly
    -- without touching the user.
    db.query([[
      CREATE FUNCTION api_users_roles_cache_api_role_ids_trigger()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        CASE TG_OP
        WHEN 'INSERT' THEN
          UPDATE api_users SET updated_at = updated_at WHERE id IN (
            SELECT api_user_id FROM new_table
          );
        WHEN 'DELETE' THEN
          UPDATE api_users SET updated_at = updated_at WHERE id IN (
            SELECT api_user_id FROM old_table
          );
        WHEN 'TRUNCATE' THEN
          UPDATE api_users SET updated_at = updated_at WHERE cached_api_role_ids IS NOT NULL;
        ELSE
          UPDATE api_users SET updated_at = updated_at WHERE id IN (
            SELECT api_user_id FROM new_table
            UNION ALL
            SELECT api_user_id FROM old_table
          );
        END CASE;
        return NULL;
      END
      $$;
    ]])
    db.query([[
      CREATE TRIGGER api_users_roles_cache_api_role_ids_insert_trigger AFTER INSERT
      ON api_users_roles
      REFERENCING NEW TABLE AS new_table
      FOR EACH STATEMENT
      EXECUTE FUNCTION api_users_roles_cache_api_role_ids_trigger();
      CREATE TRIGGER api_users_roles_cache_api_role_ids_update_trigger AFTER UPDATE
      ON api_users_roles
      REFERENCING NEW TABLE AS new_table OLD TABLE AS old_table
      FOR EACH STATEMENT
      EXECUTE FUNCTION api_users_roles_cache_api_role_ids_trigger();
      CREATE TRIGGER api_users_roles_cache_api_role_ids_delete_trigger AFTER DELETE
      ON api_users_roles
      REFERENCING OLD TABLE AS old_table
      FOR EACH STATEMENT
      EXECUTE FUNCTION api_users_roles_cache_api_role_ids_trigger();
      CREATE TRIGGER api_users_roles_cache_api_role_ids_truncate_trigger AFTER TRUNCATE
      ON api_users_roles
      FOR EACH STATEMENT
      EXECUTE FUNCTION api_users_roles_cache_api_role_ids_trigger();
    ]])

    -- Recreate the view now using the cached roles rather than needing an extra
    -- subquery.
    db.query([[
      DROP VIEW api_users_flattened;
      CREATE VIEW api_users_flattened AS
        SELECT
          u.id,
          u.api_key_prefix,
          u.api_key_hash,
          u.email,
          u.email_verified,
          u.registration_source,
          u.throttle_by_ip,
          extract(epoch from u.disabled_at)::int AS disabled_at,
          extract(epoch from u.created_at)::int AS created_at,
          jsonb_build_object(
            'allowed_ips', s.allowed_ips,
            'allowed_referers', s.allowed_referers,
            'rate_limit_mode', s.rate_limit_mode,
            'rate_limits', (
              SELECT jsonb_agg(r2.*)
              FROM (
                SELECT
                  r.duration,
                  r.limit_by,
                  r.limit_to,
                  r.distributed,
                  r.response_headers
                FROM rate_limits AS r
                WHERE r.api_user_settings_id = s.id
              ) AS r2
            )
          ) AS settings,
          cached_api_role_ids AS roles
        FROM api_users AS u
          LEFT JOIN api_user_settings AS s ON u.id = s.api_user_id;
    ]])

    -- Create an immutable function that can store the object structure of the
    -- roles (optimized for the SQL view and querying), and extract the keys for
    -- searching.
    db.query([[
      CREATE FUNCTION jsonb_object_keys_as_string(p_input jsonb)
      RETURNS text
      IMMUTABLE
      RETURNS NULL ON NULL INPUT
      PARALLEL SAFE
      LANGUAGE sql
      AS $$
        SELECT string_agg(v, ' ') FROM jsonb_object_keys(p_input) AS t(v)
      $$;
    ]])

    -- Enable pg_trgm for supporting indexes for LIKE queries.
    db.query("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    -- Create the main index used in the admin for searching over users.
    db.query([[
      CREATE INDEX api_users_search_idx ON api_users USING gin ((
        coalesce(first_name, '') || ' ' ||
        coalesce(last_name, '') || ' ' ||
        coalesce(email, '') || ' ' ||
        coalesce(registration_source, '') || ' ' ||
        coalesce(jsonb_object_keys_as_string(cached_api_role_ids), '')
      ) gin_trgm_ops)
    ]])

    -- The admin also does a separate, special prefix query for the API key.
    db.query("CREATE INDEX api_users_api_key_prefix_search_idx ON api_users USING gin (api_key_prefix gin_trgm_ops)")

    db.query("ANALYZE api_users")

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1700281762] = function()
    db.query("BEGIN")

    db.query("ALTER TABLE api_users ADD COLUMN registration_key_creator_api_user_id uuid REFERENCES api_users (id) ON DELETE RESTRICT")
    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v2_success boolean")
    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v2_error_codes varchar(50)[]")
    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v3_success boolean")
    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v3_score numeric(2, 1)")
    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v3_action varchar(255)")
    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v3_error_codes varchar(50)[]")

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1700346585] = function()
    db.query("BEGIN")

    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v2_hostname varchar(255)")
    db.query("ALTER TABLE api_users ADD COLUMN registration_recaptcha_v3_hostname varchar(255)")

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1701483732] = function()
    db.query("BEGIN")

    db.query("ALTER TABLE api_users ADD COLUMN registration_options jsonb")
    db.query("ALTER TABLE api_users ADD COLUMN registration_input_options jsonb")

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1721347955] = function()
    db.query("BEGIN")

    db.query([[
      CREATE OR REPLACE FUNCTION analytics_cache_extract_unique_user_ids()
      RETURNS TRIGGER AS $$
      BEGIN
        IF (jsonb_typeof(NEW.data->'aggregations'->'unique_user_ids'->'buckets') = 'array') THEN
          NEW.unique_user_ids := (SELECT array_agg(DISTINCT bucket->>'key')::uuid[] FROM jsonb_array_elements(NEW.data->'aggregations'->'unique_user_ids'->'buckets') AS bucket);
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1738353016] = function()
    db.query("BEGIN")

    db.query([[
      CREATE OR REPLACE AGGREGATE array_accum (anycompatiblearray) (
        sfunc = array_cat,
        stype = anycompatiblearray,
        initcond = '{}'
      )
    ]])

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1753472899] = function()
    db.query("BEGIN")

    db.query([[
      ALTER TABLE analytics_cities
        ALTER COLUMN region TYPE varchar(3)
    ]])

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1769633747] = function()
    db.query("BEGIN")

    -- Add an extra column to store the unique user IDs in a fashion more
    -- optimized for querying. But since this strategy only works if each row
    -- represents a single date bucket, add extra constraints to ensure we
    -- don't accidentally mess up this assumption in the future.
    db.query("ALTER TABLE analytics_cache ADD COLUMN data_date varchar GENERATED ALWAYS AS ((data->'aggregations'->'hits_over_time'->'buckets'->0->>'key_as_string')::varchar) STORED")
    db.query("ALTER TABLE analytics_cache ADD COLUMN hit_count bigint GENERATED ALWAYS AS ((data->'aggregations'->'hits_over_time'->'buckets'->0->>'doc_count')::bigint) STORED")
    db.query("ALTER TABLE analytics_cache ADD COLUMN response_time_average bigint GENERATED ALWAYS AS (round((data->'aggregations'->'response_time_average'->>'value')::numeric)) STORED")

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1769732670] = function()
    db.query("BEGIN")

    db.query([[
      CREATE OR REPLACE FUNCTION analytics_cache_extract_unique_user_ids()
      RETURNS TRIGGER AS $$
      BEGIN
        IF (jsonb_typeof(NEW.data->'aggregations'->'unique_user_ids'->'buckets') = 'array') THEN
          NEW.unique_user_ids := (SELECT array_agg(DISTINCT bucket->'key'->>'user_id')::uuid[] FROM jsonb_array_elements(NEW.data->'aggregations'->'unique_user_ids'->'buckets') AS bucket);
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    ]])

    db.query(grants_sql)
    db.query("COMMIT")
  end,

  [1771350000] = function()
    db.query("BEGIN")

    -- Drop old v3 sessions table and create new v4-compatible table.
    -- lua-resty-session v4 uses a completely different schema.
    db.query("DROP TRIGGER IF EXISTS sessions_stamp_record ON sessions")
    db.query("DROP TABLE sessions")
    db.query([[
      CREATE TABLE sessions(
        sid TEXT PRIMARY KEY,
        name TEXT,
        data TEXT,
        exp TIMESTAMP WITH TIME ZONE
      )
    ]])
    db.query("CREATE INDEX ON sessions(exp)")

    db.query(grants_sql)
    db.query("COMMIT")
  end,
}

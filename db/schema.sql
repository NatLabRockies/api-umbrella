SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: api_umbrella; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA api_umbrella;


--
-- Name: audit; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA audit;


--
-- Name: SCHEMA audit; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA audit IS 'Out-of-table audit/history logging tables and trigger functions';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA api_umbrella;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

-- COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

-- COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: analytics_cache_extract_unique_user_ids(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.analytics_cache_extract_unique_user_ids() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF (jsonb_typeof(NEW.data->'aggregations'->'unique_user_ids'->'buckets') = 'array') THEN
          NEW.unique_user_ids := (SELECT array_agg(DISTINCT bucket->'key'->>'user_id')::uuid[] FROM jsonb_array_elements(NEW.data->'aggregations'->'unique_user_ids'->'buckets') AS bucket);
        END IF;

        RETURN NEW;
      END;
      $$;


--
-- Name: api_users_cache_api_role_ids_trigger(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.api_users_cache_api_role_ids_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.cached_api_role_ids := (SELECT jsonb_object_agg(api_role_id, true)
              FROM api_users_roles WHERE api_user_id = NEW.id);

        return NEW;
      END
      $$;


--
-- Name: api_users_increment_version(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.api_users_increment_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
      $$;


--
-- Name: api_users_roles_cache_api_role_ids_trigger(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.api_users_roles_cache_api_role_ids_trigger() RETURNS trigger
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


--
-- Name: current_app_user_id(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.current_app_user_id() RETURNS uuid
    LANGUAGE plpgsql
    AS $$
      BEGIN
        RETURN current_setting('audit.application_user_id')::uuid;
      END;
      $$;


--
-- Name: current_app_username(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.current_app_username() RETURNS character varying
    LANGUAGE plpgsql
    AS $$
      BEGIN
        RETURN current_setting('audit.application_user_name');
      END;
      $$;


--
-- Name: distributed_rate_limit_counters_increment_version(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.distributed_rate_limit_counters_increment_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.version := nextval('distributed_rate_limit_counters_version_seq');
        return NEW;
      END;
      $$;


--
-- Name: jsonb_object_keys_as_string(jsonb); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.jsonb_object_keys_as_string(p_input jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $$
        SELECT string_agg(v, ' ') FROM jsonb_object_keys(p_input) AS t(v)
      $$;


--
-- Name: path_sort_order(text); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.path_sort_order(text) RETURNS text[]
    LANGUAGE plpgsql
    AS $_$
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
      $_$;


--
-- Name: stamp_record(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.stamp_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
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
      $_$;


--
-- Name: update_timestamp(); Type: FUNCTION; Schema: api_umbrella; Owner: -
--

CREATE FUNCTION api_umbrella.update_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
      $$;


--
-- Name: audit_table(regclass); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.audit_table(target_table regclass) RETURNS void
    LANGUAGE sql
    AS $_$
  SELECT audit.audit_table($1, BOOLEAN 't', BOOLEAN 't');
$_$;


--
-- Name: FUNCTION audit_table(target_table regclass); Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON FUNCTION audit.audit_table(target_table regclass) IS '
Add auditing support to the given table. Row-level changes will be logged with
full client query text. No cols are ignored.
';


--
-- Name: audit_table(regclass, boolean, boolean); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean) RETURNS void
    LANGUAGE sql
    AS $_$
  SELECT audit.audit_table($1, $2, $3, ARRAY[]::TEXT[]);
$_$;


--
-- Name: audit_table(regclass, boolean, boolean, text[]); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean, ignored_cols text[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  stm_targets TEXT = 'INSERT OR UPDATE OR DELETE OR TRUNCATE';
  _q_txt TEXT;
  _ignored_cols_snip TEXT = '';
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_row ON ' || target_table::TEXT;
  EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_stm ON ' || target_table::TEXT;

  IF audit_rows THEN
    IF array_length(ignored_cols,1) > 0 THEN
        _ignored_cols_snip = ', ' || quote_literal(ignored_cols);
    END IF;
    _q_txt = 'CREATE TRIGGER audit_trigger_row '
             'AFTER INSERT OR UPDATE OR DELETE ON ' ||
             target_table::TEXT ||
             ' FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func(' ||
             quote_literal(audit_query_text) ||
             _ignored_cols_snip ||
             ');';
    RAISE NOTICE '%', _q_txt;
    EXECUTE _q_txt;
    stm_targets = 'TRUNCATE';
  END IF;

  _q_txt = 'CREATE TRIGGER audit_trigger_stm AFTER ' || stm_targets || ' ON ' ||
           target_table ||
           ' FOR EACH STATEMENT EXECUTE PROCEDURE audit.if_modified_func('||
           quote_literal(audit_query_text) || ');';
  RAISE NOTICE '%', _q_txt;
  EXECUTE _q_txt;
END;
$$;


--
-- Name: FUNCTION audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean, ignored_cols text[]); Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON FUNCTION audit.audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean, ignored_cols text[]) IS '
Add auditing support to a table.

Arguments:
   target_table:     Table name, schema qualified if not on search_path
   audit_rows:       Record each row change, or only audit at a statement level
   audit_query_text: Record the text of the client query that triggered
                     the audit event?
   ignored_cols:     Columns to exclude from update diffs,
                     ignore updates that change only ignored cols.
';


--
-- Name: if_modified_func(); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.if_modified_func() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    audit_row audit.log;
    include_values BOOLEAN;
    log_diffs BOOLEAN;
    h_old JSONB;
    h_new JSONB;
    excluded_cols TEXT[] = ARRAY[]::TEXT[];
BEGIN
  IF TG_WHEN <> 'AFTER' THEN
    RAISE EXCEPTION 'audit.if_modified_func() may only run as an AFTER trigger';
  END IF;

  audit_row = ROW(
    nextval('audit.log_id_seq'),                    -- id
    TG_TABLE_SCHEMA::TEXT,                          -- schema_name
    TG_TABLE_NAME::TEXT,                            -- table_name
    TG_RELID,                                       -- relation OID for faster searches
    session_user::TEXT,                             -- session_user_name
    current_user::TEXT,                             -- current_user_name
    current_timestamp,                              -- action_tstamp_tx
    statement_timestamp(),                          -- action_tstamp_stm
    clock_timestamp(),                              -- action_tstamp_clk
    txid_current(),                                 -- transaction ID
    current_setting('audit.application_name', true),      -- client application
    current_setting('audit.application_user_name', true), -- client user name
    inet_client_addr(),                             -- client_addr
    inet_client_port(),                             -- client_port
    current_query(),                                -- top-level query or queries
    substring(TG_OP, 1, 1),                         -- action
    NULL,                                           -- row_data
    NULL,                                           -- changed_fields
    'f'                                             -- statement_only
    );

  IF NOT TG_ARGV[0]::BOOLEAN IS DISTINCT FROM 'f'::BOOLEAN THEN
    audit_row.client_query = NULL;
  END IF;

  IF TG_ARGV[1] IS NOT NULL THEN
    excluded_cols = TG_ARGV[1]::TEXT[];
  END IF;

  IF (TG_OP = 'INSERT' AND TG_LEVEL = 'ROW') THEN
    audit_row.changed_fields = jsonb_minus(to_jsonb(NEW.*), excluded_cols);
  ELSIF (TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW') THEN
    audit_row.row_data = jsonb_minus(to_jsonb(OLD.*), excluded_cols);
    audit_row.changed_fields =
      jsonb_minus(jsonb_minus(to_jsonb(NEW.*), audit_row.row_data), excluded_cols);
    IF audit_row.changed_fields = '{}'::JSONB THEN
      -- All changed fields are ignored. Skip this update.
      RETURN NULL;
    END IF;
  ELSIF (TG_OP = 'DELETE' AND TG_LEVEL = 'ROW') THEN
    audit_row.row_data = jsonb_minus(to_jsonb(OLD.*), excluded_cols);
  ELSIF (TG_LEVEL = 'STATEMENT' AND
         TG_OP IN ('INSERT','UPDATE','DELETE','TRUNCATE')) THEN
    audit_row.statement_only = 't';
  ELSE
    RAISE EXCEPTION '[audit.if_modified_func] - Trigger func added as trigger '
                    'for unhandled case: %, %', TG_OP, TG_LEVEL;
    RETURN NULL;
  END IF;
  INSERT INTO audit.log VALUES (audit_row.*);
  RETURN NULL;
END;
$$;


--
-- Name: FUNCTION if_modified_func(); Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON FUNCTION audit.if_modified_func() IS '
Track changes to a table at the statement and/or row level.

Optional parameters to trigger in CREATE TRIGGER call:

param 0: BOOLEAN, whether to log the query text. Default ''t''.

param 1: TEXT[], columns to ignore in updates. Default [].

         Updates to ignored cols are omitted from changed_fields.

         Updates with only ignored cols changed are not inserted
         into the audit log.

         Almost all the processing work is still done for updates
         that ignored. If you need to save the load, you need to use
         WHEN clause on the trigger instead.

         No warning or error is issued if ignored_cols contains columns
         that do not exist in the target table. This lets you specify
         a standard set of ignored columns.

There is no parameter to disable logging of values. Add this trigger as
a ''FOR EACH STATEMENT'' rather than ''FOR EACH ROW'' trigger if you do not
want to log row values.

Note that the user name logged is the login role for the session. The audit
trigger cannot obtain the active role because it is reset by
the SECURITY DEFINER invocation of the audit trigger its self.
';


--
-- Name: jsonb_minus(jsonb, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jsonb_minus("left" jsonb, keys text[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  SELECT
    CASE
      WHEN "left" ?| "keys"
        THEN COALESCE(
          (SELECT ('{' ||
                    string_agg(to_json("key")::TEXT || ':' || "value", ',') ||
                    '}')
             FROM jsonb_each("left")
            WHERE "key" <> ALL ("keys")),
          '{}'
        )::JSONB
      ELSE "left"
    END
$$;


--
-- Name: FUNCTION jsonb_minus("left" jsonb, keys text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.jsonb_minus("left" jsonb, keys text[]) IS 'Delete specificed keys';


--
-- Name: jsonb_minus(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jsonb_minus("left" jsonb, "right" jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  SELECT
    COALESCE(json_object_agg(
      "key",
      CASE
        -- if the value is an object and the value of the second argument is
        -- not null, we do a recursion
        WHEN jsonb_typeof("value") = 'object' AND "right" -> "key" IS NOT NULL
        THEN jsonb_minus("value", "right" -> "key")
        -- for all the other types, we just return the value
        ELSE "value"
      END
    ), '{}')::JSONB
  FROM
    jsonb_each("left")
  WHERE
    "left" -> "key" <> "right" -> "key"
    OR "right" -> "key" IS NULL
$$;


--
-- Name: FUNCTION jsonb_minus("left" jsonb, "right" jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.jsonb_minus("left" jsonb, "right" jsonb) IS 'Delete matching pairs in the right argument from the left argument';


--
-- Name: array_accum(anycompatiblearray); Type: AGGREGATE; Schema: api_umbrella; Owner: -
--

CREATE AGGREGATE api_umbrella.array_accum(anycompatiblearray) (
    SFUNC = array_cat,
    STYPE = anycompatiblearray,
    INITCOND = '{}'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_groups; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.admin_groups (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: admin_groups_admin_permissions; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.admin_groups_admin_permissions (
    admin_group_id uuid NOT NULL,
    admin_permission_id character varying(50) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: admin_groups_admins; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.admin_groups_admins (
    admin_group_id uuid NOT NULL,
    admin_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: admin_groups_api_scopes; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.admin_groups_api_scopes (
    admin_group_id uuid NOT NULL,
    api_scope_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: admin_permissions; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.admin_permissions (
    id character varying(50) NOT NULL,
    name character varying(255) NOT NULL,
    display_order smallint NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: admins; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.admins (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    username character varying(255) NOT NULL,
    email character varying(255),
    name character varying(255),
    notes text,
    superuser boolean DEFAULT false NOT NULL,
    authentication_token_hash character varying(64) NOT NULL,
    authentication_token_encrypted character varying(76) NOT NULL,
    authentication_token_encrypted_iv character varying(12) NOT NULL,
    current_sign_in_provider character varying(100),
    last_sign_in_provider character varying(100),
    password_hash character varying(60),
    reset_password_token_hash character varying(64),
    reset_password_sent_at timestamp with time zone,
    remember_created_at timestamp with time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    current_sign_in_ip inet,
    last_sign_in_ip inet,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token_hash character varying(64),
    locked_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: analytics_cache; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.analytics_cache (
    id character varying(64) NOT NULL,
    id_data jsonb NOT NULL,
    data jsonb NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT transaction_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT transaction_timestamp() NOT NULL,
    unique_user_ids uuid[],
    data_date character varying GENERATED ALWAYS AS (((((((data -> 'aggregations'::text) -> 'hits_over_time'::text) -> 'buckets'::text) -> 0) ->> 'key_as_string'::text))::character varying) STORED,
    hit_count bigint GENERATED ALWAYS AS (((((((data -> 'aggregations'::text) -> 'hits_over_time'::text) -> 'buckets'::text) -> 0) ->> 'doc_count'::text))::bigint) STORED,
    response_time_average bigint GENERATED ALWAYS AS (round(((((data -> 'aggregations'::text) -> 'response_time_average'::text) ->> 'value'::text))::numeric)) STORED,
    CONSTRAINT analytics_cache_enforce_single_date_bucket CHECK ((NOT (jsonb_array_length((((data -> 'aggregations'::text) -> 'hits_over_time'::text) -> 'buckets'::text)) > 1)))
);


--
-- Name: analytics_cities; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.analytics_cities (
    id integer NOT NULL,
    country character varying(2) NOT NULL,
    region character varying(3),
    city character varying(200),
    location point NOT NULL,
    created_at timestamp with time zone DEFAULT transaction_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT transaction_timestamp() NOT NULL
);


--
-- Name: analytics_cities_id_seq; Type: SEQUENCE; Schema: api_umbrella; Owner: -
--

CREATE SEQUENCE api_umbrella.analytics_cities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: analytics_cities_id_seq; Type: SEQUENCE OWNED BY; Schema: api_umbrella; Owner: -
--

ALTER SEQUENCE api_umbrella.analytics_cities_id_seq OWNED BY api_umbrella.analytics_cities.id;


--
-- Name: api_backend_http_headers; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backend_http_headers (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_backend_settings_id uuid NOT NULL,
    header_type character varying(17) NOT NULL,
    sort_order integer NOT NULL,
    key character varying(255) NOT NULL,
    value character varying(255),
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    CONSTRAINT api_backend_http_headers_header_type_check CHECK (((header_type)::text = ANY (ARRAY[('request'::character varying)::text, ('response_default'::character varying)::text, ('response_override'::character varying)::text])))
);


--
-- Name: api_backend_rewrites; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backend_rewrites (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_backend_id uuid NOT NULL,
    matcher_type character varying(5) NOT NULL,
    http_method character varying(7) NOT NULL,
    frontend_matcher character varying(255) NOT NULL,
    backend_replacement character varying(255) NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    CONSTRAINT api_backend_rewrites_http_method_check CHECK (((http_method)::text = ANY (ARRAY[('any'::character varying)::text, ('GET'::character varying)::text, ('POST'::character varying)::text, ('PUT'::character varying)::text, ('DELETE'::character varying)::text, ('HEAD'::character varying)::text, ('TRACE'::character varying)::text, ('OPTIONS'::character varying)::text, ('CONNECT'::character varying)::text, ('PATCH'::character varying)::text]))),
    CONSTRAINT api_backend_rewrites_matcher_type_check CHECK (((matcher_type)::text = ANY (ARRAY[('route'::character varying)::text, ('regex'::character varying)::text])))
);


--
-- Name: api_backend_servers; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backend_servers (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_backend_id uuid NOT NULL,
    host character varying(255) NOT NULL,
    port integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: api_backend_settings; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backend_settings (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_backend_id uuid,
    api_backend_sub_url_settings_id uuid,
    append_query_string character varying(255),
    http_basic_auth character varying(255),
    require_https character varying(23),
    require_https_transition_start_at timestamp with time zone,
    redirect_https boolean DEFAULT false NOT NULL,
    disable_api_key boolean,
    api_key_verification_level character varying(16),
    api_key_verification_transition_start_at timestamp with time zone,
    required_roles_override boolean DEFAULT false NOT NULL,
    pass_api_key_header boolean DEFAULT false NOT NULL,
    pass_api_key_query_param boolean DEFAULT false NOT NULL,
    rate_limit_bucket_name character varying(255),
    rate_limit_mode character varying(9),
    anonymous_rate_limit_behavior character varying(11),
    authenticated_rate_limit_behavior character varying(12),
    error_templates jsonb,
    error_data jsonb,
    allowed_ips inet[],
    allowed_referers character varying(500)[],
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    CONSTRAINT api_backend_settings_anonymous_rate_limit_behavior_check CHECK (((anonymous_rate_limit_behavior)::text = ANY (ARRAY[('ip_fallback'::character varying)::text, ('ip_only'::character varying)::text]))),
    CONSTRAINT api_backend_settings_api_key_verification_level_check CHECK (((api_key_verification_level)::text = ANY (ARRAY[('none'::character varying)::text, ('transition_email'::character varying)::text, ('required_email'::character varying)::text]))),
    CONSTRAINT api_backend_settings_authenticated_rate_limit_behavior_check CHECK (((authenticated_rate_limit_behavior)::text = ANY (ARRAY[('all'::character varying)::text, ('api_key_only'::character varying)::text]))),
    CONSTRAINT api_backend_settings_rate_limit_mode_check CHECK (((rate_limit_mode)::text = ANY (ARRAY[('unlimited'::character varying)::text, ('custom'::character varying)::text]))),
    CONSTRAINT api_backend_settings_require_https_check CHECK (((require_https)::text = ANY (ARRAY[('required_return_error'::character varying)::text, ('transition_return_error'::character varying)::text, ('optional'::character varying)::text]))),
    CONSTRAINT parent_id_not_null CHECK ((((api_backend_id IS NOT NULL) AND (api_backend_sub_url_settings_id IS NULL)) OR ((api_backend_id IS NULL) AND (api_backend_sub_url_settings_id IS NOT NULL))))
);


--
-- Name: api_backend_settings_required_roles; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backend_settings_required_roles (
    api_backend_settings_id uuid NOT NULL,
    api_role_id character varying(255) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: api_backend_sub_url_settings; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backend_sub_url_settings (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_backend_id uuid NOT NULL,
    http_method character varying(7) NOT NULL,
    regex character varying(255) NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    CONSTRAINT api_backend_sub_url_settings_http_method_check CHECK (((http_method)::text = ANY (ARRAY[('any'::character varying)::text, ('GET'::character varying)::text, ('POST'::character varying)::text, ('PUT'::character varying)::text, ('DELETE'::character varying)::text, ('HEAD'::character varying)::text, ('TRACE'::character varying)::text, ('OPTIONS'::character varying)::text, ('CONNECT'::character varying)::text, ('PATCH'::character varying)::text])))
);


--
-- Name: api_backend_url_matches; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backend_url_matches (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_backend_id uuid NOT NULL,
    frontend_prefix character varying(255) NOT NULL,
    backend_prefix character varying(255) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: api_backends; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_backends (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    backend_protocol character varying(5) NOT NULL,
    frontend_host character varying(255) NOT NULL,
    backend_host character varying(255),
    balance_algorithm character varying(11) NOT NULL,
    keepalive_connections smallint,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    organization_name character varying(255),
    status_description character varying(255),
    created_order integer NOT NULL,
    CONSTRAINT api_backends_backend_protocol_check CHECK (((backend_protocol)::text = ANY (ARRAY[('http'::character varying)::text, ('https'::character varying)::text]))),
    CONSTRAINT api_backends_balance_algorithm_check CHECK (((balance_algorithm)::text = ANY (ARRAY[('round_robin'::character varying)::text, ('least_conn'::character varying)::text, ('ip_hash'::character varying)::text])))
);


--
-- Name: api_backends_created_order_seq; Type: SEQUENCE; Schema: api_umbrella; Owner: -
--

ALTER TABLE api_umbrella.api_backends ALTER COLUMN created_order ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME api_umbrella.api_backends_created_order_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_roles; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_roles (
    id character varying(255) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: api_scopes; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_scopes (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    host character varying(255) NOT NULL,
    path_prefix character varying(255) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: api_user_settings; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_user_settings (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_user_id uuid NOT NULL,
    rate_limit_mode character varying(9),
    allowed_ips inet[],
    allowed_referers character varying(500)[],
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    CONSTRAINT api_user_settings_rate_limit_mode_check CHECK (((rate_limit_mode)::text = ANY (ARRAY[('unlimited'::character varying)::text, ('custom'::character varying)::text])))
);


--
-- Name: api_users; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_users (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    version bigint NOT NULL,
    api_key_hash character varying(64) NOT NULL,
    api_key_encrypted character varying(76) NOT NULL,
    api_key_encrypted_iv character varying(12) NOT NULL,
    api_key_prefix character varying(16) NOT NULL,
    email character varying(255) NOT NULL,
    email_verified boolean DEFAULT false NOT NULL,
    first_name character varying(80),
    last_name character varying(80),
    use_description character varying(2000),
    website character varying(255),
    metadata jsonb,
    registration_ip inet,
    registration_source character varying(255),
    registration_user_agent character varying(1000),
    registration_referer character varying(1000),
    registration_origin character varying(1000),
    throttle_by_ip boolean DEFAULT false NOT NULL,
    disabled_at timestamp with time zone,
    imported boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    cached_api_role_ids jsonb,
    registration_key_creator_api_user_id uuid,
    registration_recaptcha_v2_success boolean,
    registration_recaptcha_v2_error_codes character varying(50)[],
    registration_recaptcha_v3_success boolean,
    registration_recaptcha_v3_score numeric(2,1),
    registration_recaptcha_v3_action character varying(255),
    registration_recaptcha_v3_error_codes character varying(50)[],
    registration_recaptcha_v2_hostname character varying(255),
    registration_recaptcha_v3_hostname character varying(255),
    registration_options jsonb,
    registration_input_options jsonb
);


--
-- Name: rate_limits; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.rate_limits (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    api_backend_settings_id uuid,
    api_user_settings_id uuid,
    duration bigint NOT NULL,
    limit_by character varying(7) NOT NULL,
    limit_to bigint NOT NULL,
    distributed boolean DEFAULT false NOT NULL,
    response_headers boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    CONSTRAINT rate_limits_limit_by_check CHECK (((limit_by)::text = ANY (ARRAY[('ip'::character varying)::text, ('api_key'::character varying)::text]))),
    CONSTRAINT settings_id_not_null CHECK ((((api_backend_settings_id IS NOT NULL) AND (api_user_settings_id IS NULL)) OR ((api_backend_settings_id IS NULL) AND (api_user_settings_id IS NOT NULL))))
);


--
-- Name: api_users_flattened; Type: VIEW; Schema: api_umbrella; Owner: -
--

CREATE VIEW api_umbrella.api_users_flattened AS
 SELECT u.id,
    u.api_key_prefix,
    u.api_key_hash,
    u.email,
    u.email_verified,
    u.registration_source,
    u.throttle_by_ip,
    (date_part('epoch'::text, u.disabled_at))::integer AS disabled_at,
    (date_part('epoch'::text, u.created_at))::integer AS created_at,
    jsonb_build_object('allowed_ips', s.allowed_ips, 'allowed_referers', s.allowed_referers, 'rate_limit_mode', s.rate_limit_mode, 'rate_limits', ( SELECT jsonb_agg(r2.*) AS jsonb_agg
           FROM ( SELECT r.duration,
                    r.limit_by,
                    r.limit_to,
                    r.distributed,
                    r.response_headers
                   FROM api_umbrella.rate_limits r
                  WHERE (r.api_user_settings_id = s.id)) r2)) AS settings,
    u.cached_api_role_ids AS roles
   FROM (api_umbrella.api_users u
     LEFT JOIN api_umbrella.api_user_settings s ON ((u.id = s.api_user_id)));


--
-- Name: api_users_roles; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.api_users_roles (
    api_user_id uuid NOT NULL,
    api_role_id character varying(255) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: api_users_version_seq; Type: SEQUENCE; Schema: api_umbrella; Owner: -
--

CREATE SEQUENCE api_umbrella.api_users_version_seq
    START WITH -9223372036854775807
    INCREMENT BY 1
    MINVALUE -9223372036854775807
    NO MAXVALUE
    CACHE 1;


--
-- Name: cache; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.cache (
    id character varying(255) NOT NULL,
    data bytea NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT transaction_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT transaction_timestamp() NOT NULL
);


--
-- Name: distributed_rate_limit_counters; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE UNLOGGED TABLE api_umbrella.distributed_rate_limit_counters (
    id character varying(500) NOT NULL,
    version bigint NOT NULL,
    value bigint NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: distributed_rate_limit_counters_version_seq; Type: SEQUENCE; Schema: api_umbrella; Owner: -
--

CREATE SEQUENCE api_umbrella.distributed_rate_limit_counters_version_seq
    START WITH -9223372036854775807
    INCREMENT BY 1
    MINVALUE -9223372036854775807
    NO MAXVALUE
    CACHE 1
    CYCLE;


--
-- Name: lapis_migrations; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.lapis_migrations (
    name character varying(255) NOT NULL
);


--
-- Name: published_config; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.published_config (
    id bigint NOT NULL,
    config jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL
);


--
-- Name: published_config_id_seq; Type: SEQUENCE; Schema: api_umbrella; Owner: -
--

CREATE SEQUENCE api_umbrella.published_config_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: published_config_id_seq; Type: SEQUENCE OWNED BY; Schema: api_umbrella; Owner: -
--

ALTER SEQUENCE api_umbrella.published_config_id_seq OWNED BY api_umbrella.published_config.id;


--
-- Name: sessions; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.sessions (
    sid text NOT NULL,
    name text,
    data text,
    exp timestamp with time zone
);


--
-- Name: website_backends; Type: TABLE; Schema: api_umbrella; Owner: -
--

CREATE TABLE api_umbrella.website_backends (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    frontend_host character varying(255) NOT NULL,
    backend_protocol character varying(5) NOT NULL,
    server_host character varying(255) NOT NULL,
    server_port integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by_id uuid NOT NULL,
    created_by_username character varying(255) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    updated_by_id uuid NOT NULL,
    updated_by_username character varying(255) NOT NULL,
    created_order integer NOT NULL,
    CONSTRAINT website_backends_backend_protocol_check CHECK (((backend_protocol)::text = ANY (ARRAY[('http'::character varying)::text, ('https'::character varying)::text])))
);


--
-- Name: website_backends_created_order_seq; Type: SEQUENCE; Schema: api_umbrella; Owner: -
--

ALTER TABLE api_umbrella.website_backends ALTER COLUMN created_order ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME api_umbrella.website_backends_created_order_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: legacy_log; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.legacy_log (
    id bigint NOT NULL,
    version bigint NOT NULL,
    original_class character varying(255) NOT NULL,
    original_class_id character varying(36) NOT NULL,
    altered_attributes jsonb NOT NULL,
    full_attributes jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: legacy_log_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

CREATE SEQUENCE audit.legacy_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: legacy_log_id_seq; Type: SEQUENCE OWNED BY; Schema: audit; Owner: -
--

ALTER SEQUENCE audit.legacy_log_id_seq OWNED BY audit.legacy_log.id;


--
-- Name: log; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.log (
    id bigint NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    relid oid NOT NULL,
    session_user_name text NOT NULL,
    current_user_name text NOT NULL,
    action_tstamp_tx timestamp with time zone NOT NULL,
    action_tstamp_stm timestamp with time zone NOT NULL,
    action_tstamp_clk timestamp with time zone NOT NULL,
    transaction_id bigint NOT NULL,
    application_name text,
    application_user_name text,
    client_addr inet,
    client_port integer,
    client_query text,
    action text NOT NULL,
    row_data jsonb,
    changed_fields jsonb,
    statement_only boolean NOT NULL,
    CONSTRAINT log_action_check CHECK ((action = ANY (ARRAY['I'::text, 'D'::text, 'U'::text, 'T'::text])))
);


--
-- Name: TABLE log; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON TABLE audit.log IS 'History of auditable actions on audited tables';


--
-- Name: COLUMN log.id; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.id IS 'Unique identifier for each auditable event';


--
-- Name: COLUMN log.schema_name; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.schema_name IS 'Database schema audited table for this event is in';


--
-- Name: COLUMN log.table_name; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.table_name IS 'Non-schema-qualified table name of table event occured in';


--
-- Name: COLUMN log.relid; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.relid IS 'Table OID. Changes with drop/create. Get with ''tablename''::REGCLASS';


--
-- Name: COLUMN log.session_user_name; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.session_user_name IS 'Login / session user whose statement caused the audited event';


--
-- Name: COLUMN log.current_user_name; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.current_user_name IS 'Effective user that cased audited event (if authorization level changed)';


--
-- Name: COLUMN log.action_tstamp_tx; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.action_tstamp_tx IS 'Transaction start timestamp for tx in which audited event occurred';


--
-- Name: COLUMN log.action_tstamp_stm; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.action_tstamp_stm IS 'Statement start timestamp for tx in which audited event occurred';


--
-- Name: COLUMN log.action_tstamp_clk; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.action_tstamp_clk IS 'Wall clock time at which audited event''s trigger call occurred';


--
-- Name: COLUMN log.transaction_id; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.transaction_id IS 'Identifier of transaction that made the change. Unique when paired with action_tstamp_tx.';


--
-- Name: COLUMN log.application_name; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.application_name IS 'Client-set session application name when this audit event occurred.';


--
-- Name: COLUMN log.application_user_name; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.application_user_name IS 'Client-set session application user when this audit event occurred.';


--
-- Name: COLUMN log.client_addr; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.client_addr IS 'IP address of client that issued query. Null for unix domain socket.';


--
-- Name: COLUMN log.client_port; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.client_port IS 'Port address of client that issued query. Undefined for unix socket.';


--
-- Name: COLUMN log.client_query; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.client_query IS 'Top-level query that caused this auditable event. May be more than one.';


--
-- Name: COLUMN log.action; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.action IS 'Action type; I = insert, D = delete, U = update, T = truncate';


--
-- Name: COLUMN log.row_data; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.row_data IS 'Record value. Null for statement-level trigger. For INSERT this is null. For DELETE and UPDATE it is the old tuple.';


--
-- Name: COLUMN log.changed_fields; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.changed_fields IS 'New values of fields for INSERT or changed by UPDATE. Null for DELETE';


--
-- Name: COLUMN log.statement_only; Type: COMMENT; Schema: audit; Owner: -
--

COMMENT ON COLUMN audit.log.statement_only IS '''t'' if audit event is from an FOR EACH STATEMENT trigger, ''f'' for FOR EACH ROW';


--
-- Name: log_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

CREATE SEQUENCE audit.log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_id_seq; Type: SEQUENCE OWNED BY; Schema: audit; Owner: -
--

ALTER SEQUENCE audit.log_id_seq OWNED BY audit.log.id;


--
-- Name: analytics_cities id; Type: DEFAULT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.analytics_cities ALTER COLUMN id SET DEFAULT nextval('api_umbrella.analytics_cities_id_seq'::regclass);


--
-- Name: published_config id; Type: DEFAULT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.published_config ALTER COLUMN id SET DEFAULT nextval('api_umbrella.published_config_id_seq'::regclass);


--
-- Name: legacy_log id; Type: DEFAULT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.legacy_log ALTER COLUMN id SET DEFAULT nextval('audit.legacy_log_id_seq'::regclass);


--
-- Name: log id; Type: DEFAULT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.log ALTER COLUMN id SET DEFAULT nextval('audit.log_id_seq'::regclass);


--
-- Name: admin_groups_admin_permissions admin_groups_admin_permissions_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_admin_permissions
    ADD CONSTRAINT admin_groups_admin_permissions_pkey PRIMARY KEY (admin_group_id, admin_permission_id);


--
-- Name: admin_groups_admins admin_groups_admins_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_admins
    ADD CONSTRAINT admin_groups_admins_pkey PRIMARY KEY (admin_group_id, admin_id);


--
-- Name: admin_groups_api_scopes admin_groups_api_scopes_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_api_scopes
    ADD CONSTRAINT admin_groups_api_scopes_pkey PRIMARY KEY (admin_group_id, api_scope_id);


--
-- Name: admin_groups admin_groups_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups
    ADD CONSTRAINT admin_groups_pkey PRIMARY KEY (id);


--
-- Name: admin_permissions admin_permissions_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_permissions
    ADD CONSTRAINT admin_permissions_pkey PRIMARY KEY (id);


--
-- Name: admins admins_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admins
    ADD CONSTRAINT admins_pkey PRIMARY KEY (id);


--
-- Name: analytics_cache analytics_cache_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.analytics_cache
    ADD CONSTRAINT analytics_cache_pkey PRIMARY KEY (id);


--
-- Name: analytics_cities analytics_cities_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.analytics_cities
    ADD CONSTRAINT analytics_cities_pkey PRIMARY KEY (id);


--
-- Name: api_backend_http_headers api_backend_http_headers_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_http_headers
    ADD CONSTRAINT api_backend_http_headers_pkey PRIMARY KEY (id);


--
-- Name: api_backend_http_headers api_backend_http_headers_sort_order_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_http_headers
    ADD CONSTRAINT api_backend_http_headers_sort_order_uniq UNIQUE (api_backend_settings_id, header_type, sort_order) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_backend_rewrites api_backend_rewrites_frontend_matcher_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_rewrites
    ADD CONSTRAINT api_backend_rewrites_frontend_matcher_uniq UNIQUE (api_backend_id, matcher_type, http_method, frontend_matcher) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_backend_rewrites api_backend_rewrites_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_rewrites
    ADD CONSTRAINT api_backend_rewrites_pkey PRIMARY KEY (id);


--
-- Name: api_backend_rewrites api_backend_rewrites_sort_order_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_rewrites
    ADD CONSTRAINT api_backend_rewrites_sort_order_uniq UNIQUE (api_backend_id, sort_order) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_backend_servers api_backend_servers_host_port_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_servers
    ADD CONSTRAINT api_backend_servers_host_port_uniq UNIQUE (api_backend_id, host, port) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_backend_servers api_backend_servers_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_servers
    ADD CONSTRAINT api_backend_servers_pkey PRIMARY KEY (id);


--
-- Name: api_backend_settings api_backend_settings_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_settings
    ADD CONSTRAINT api_backend_settings_pkey PRIMARY KEY (id);


--
-- Name: api_backend_settings_required_roles api_backend_settings_required_roles_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_settings_required_roles
    ADD CONSTRAINT api_backend_settings_required_roles_pkey PRIMARY KEY (api_backend_settings_id, api_role_id);


--
-- Name: api_backend_sub_url_settings api_backend_sub_url_settings_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_sub_url_settings
    ADD CONSTRAINT api_backend_sub_url_settings_pkey PRIMARY KEY (id);


--
-- Name: api_backend_sub_url_settings api_backend_sub_url_settings_regex_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_sub_url_settings
    ADD CONSTRAINT api_backend_sub_url_settings_regex_uniq UNIQUE (api_backend_id, http_method, regex) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_backend_sub_url_settings api_backend_sub_url_settings_sort_order_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_sub_url_settings
    ADD CONSTRAINT api_backend_sub_url_settings_sort_order_uniq UNIQUE (api_backend_id, sort_order) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_backend_url_matches api_backend_url_matches_frontend_prefix_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_url_matches
    ADD CONSTRAINT api_backend_url_matches_frontend_prefix_uniq UNIQUE (api_backend_id, frontend_prefix) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_backend_url_matches api_backend_url_matches_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_url_matches
    ADD CONSTRAINT api_backend_url_matches_pkey PRIMARY KEY (id);


--
-- Name: api_backends api_backends_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backends
    ADD CONSTRAINT api_backends_pkey PRIMARY KEY (id);


--
-- Name: api_roles api_roles_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_roles
    ADD CONSTRAINT api_roles_pkey PRIMARY KEY (id);


--
-- Name: api_scopes api_scopes_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_scopes
    ADD CONSTRAINT api_scopes_pkey PRIMARY KEY (id);


--
-- Name: api_user_settings api_user_settings_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_user_settings
    ADD CONSTRAINT api_user_settings_pkey PRIMARY KEY (id);


--
-- Name: api_users api_users_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_users
    ADD CONSTRAINT api_users_pkey PRIMARY KEY (id);


--
-- Name: api_users_roles api_users_roles_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_users_roles
    ADD CONSTRAINT api_users_roles_pkey PRIMARY KEY (api_user_id, api_role_id);


--
-- Name: cache cache_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.cache
    ADD CONSTRAINT cache_pkey PRIMARY KEY (id);


--
-- Name: distributed_rate_limit_counters distributed_rate_limit_counters_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.distributed_rate_limit_counters
    ADD CONSTRAINT distributed_rate_limit_counters_pkey PRIMARY KEY (id);


--
-- Name: lapis_migrations lapis_migrations_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.lapis_migrations
    ADD CONSTRAINT lapis_migrations_pkey PRIMARY KEY (name);


--
-- Name: published_config published_config_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.published_config
    ADD CONSTRAINT published_config_pkey PRIMARY KEY (id);


--
-- Name: rate_limits rate_limits_duration_uniq; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.rate_limits
    ADD CONSTRAINT rate_limits_duration_uniq UNIQUE (api_backend_settings_id, api_user_settings_id, limit_by, duration) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: rate_limits rate_limits_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.rate_limits
    ADD CONSTRAINT rate_limits_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (sid);


--
-- Name: website_backends website_backends_pkey; Type: CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.website_backends
    ADD CONSTRAINT website_backends_pkey PRIMARY KEY (id);


--
-- Name: legacy_log legacy_log_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.legacy_log
    ADD CONSTRAINT legacy_log_pkey PRIMARY KEY (id);


--
-- Name: log log_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.log
    ADD CONSTRAINT log_pkey PRIMARY KEY (id);


--
-- Name: admin_groups_name_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX admin_groups_name_idx ON api_umbrella.admin_groups USING btree (name);


--
-- Name: admin_permissions_display_order_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX admin_permissions_display_order_idx ON api_umbrella.admin_permissions USING btree (display_order);


--
-- Name: admins_authentication_token_hash_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX admins_authentication_token_hash_idx ON api_umbrella.admins USING btree (authentication_token_hash);


--
-- Name: admins_reset_password_token_hash_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX admins_reset_password_token_hash_idx ON api_umbrella.admins USING btree (reset_password_token_hash);


--
-- Name: admins_unlock_token_hash_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX admins_unlock_token_hash_idx ON api_umbrella.admins USING btree (unlock_token_hash);


--
-- Name: admins_username_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX admins_username_idx ON api_umbrella.admins USING btree (username);


--
-- Name: analytics_cache_expires_at_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX analytics_cache_expires_at_idx ON api_umbrella.analytics_cache USING btree (expires_at);


--
-- Name: analytics_cities_country_region_city_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX analytics_cities_country_region_city_idx ON api_umbrella.analytics_cities USING btree (country, region, city);


--
-- Name: api_backend_settings_api_backend_id_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_backend_settings_api_backend_id_idx ON api_umbrella.api_backend_settings USING btree (api_backend_id);


--
-- Name: api_backend_settings_api_backend_sub_url_settings_id_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_backend_settings_api_backend_sub_url_settings_id_idx ON api_umbrella.api_backend_settings USING btree (api_backend_sub_url_settings_id);


--
-- Name: api_backend_settings_required_api_backend_settings_id_api_r_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_backend_settings_required_api_backend_settings_id_api_r_idx ON api_umbrella.api_backend_settings_required_roles USING btree (api_backend_settings_id, api_role_id);


--
-- Name: api_scopes_host_path_prefix_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_scopes_host_path_prefix_idx ON api_umbrella.api_scopes USING btree (host, path_prefix);


--
-- Name: api_users_api_key_hash_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_users_api_key_hash_idx ON api_umbrella.api_users USING btree (api_key_hash);


--
-- Name: api_users_api_key_prefix_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_users_api_key_prefix_idx ON api_umbrella.api_users USING btree (api_key_prefix);


--
-- Name: api_users_api_key_prefix_search_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX api_users_api_key_prefix_search_idx ON api_umbrella.api_users USING gin (api_key_prefix api_umbrella.gin_trgm_ops);


--
-- Name: api_users_created_at_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX api_users_created_at_idx ON api_umbrella.api_users USING btree (created_at DESC);


--
-- Name: api_users_roles_api_user_id_api_role_id_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_users_roles_api_user_id_api_role_id_idx ON api_umbrella.api_users_roles USING btree (api_user_id, api_role_id);


--
-- Name: api_users_search_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX api_users_search_idx ON api_umbrella.api_users USING gin (((((((((((COALESCE(first_name, ''::character varying))::text || ' '::text) || (COALESCE(last_name, ''::character varying))::text) || ' '::text) || (COALESCE(email, ''::character varying))::text) || ' '::text) || (COALESCE(registration_source, ''::character varying))::text) || ' '::text) || COALESCE(api_umbrella.jsonb_object_keys_as_string(cached_api_role_ids), ''::text))) api_umbrella.gin_trgm_ops);


--
-- Name: api_users_version_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX api_users_version_idx ON api_umbrella.api_users USING btree (version);


--
-- Name: cache_expires_at_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX cache_expires_at_idx ON api_umbrella.cache USING btree (expires_at);


--
-- Name: distributed_rate_limit_counters_expires_at_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX distributed_rate_limit_counters_expires_at_idx ON api_umbrella.distributed_rate_limit_counters USING btree (expires_at);


--
-- Name: distributed_rate_limit_counters_version_expires_at_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX distributed_rate_limit_counters_version_expires_at_idx ON api_umbrella.distributed_rate_limit_counters USING btree (version, expires_at);


--
-- Name: distributed_rate_limit_counters_version_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX distributed_rate_limit_counters_version_idx ON api_umbrella.distributed_rate_limit_counters USING btree (version);


--
-- Name: sessions_expires_at_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE INDEX sessions_exp_idx ON api_umbrella.sessions USING btree (exp);


--
-- Name: website_backends_frontend_host_idx; Type: INDEX; Schema: api_umbrella; Owner: -
--

CREATE UNIQUE INDEX website_backends_frontend_host_idx ON api_umbrella.website_backends USING btree (frontend_host);


--
-- Name: log_action_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX log_action_idx ON audit.log USING btree (action);


--
-- Name: log_action_tstamp_tx_stm_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX log_action_tstamp_tx_stm_idx ON audit.log USING btree (action_tstamp_stm);


--
-- Name: log_application_user_name_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX log_application_user_name_idx ON audit.log USING btree (application_user_name);


--
-- Name: log_expr_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX log_expr_idx ON audit.log USING btree (((row_data ->> 'id'::text)));


--
-- Name: log_relid_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX log_relid_idx ON audit.log USING btree (relid);


--
-- Name: log_schema_name_table_name_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX log_schema_name_table_name_idx ON audit.log USING btree (schema_name, table_name);


--
-- Name: admin_groups_admin_permissions admin_groups_admin_permissions_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER admin_groups_admin_permissions_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups_admin_permissions FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"admin_groups","primary_key":"id","foreign_key":"admin_group_id"}]');


--
-- Name: admin_groups_admins admin_groups_admins_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER admin_groups_admins_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups_admins FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"admins","primary_key":"id","foreign_key":"admin_id"}]');


--
-- Name: admin_groups_api_scopes admin_groups_api_scopes_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER admin_groups_api_scopes_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups_api_scopes FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"admin_groups","primary_key":"id","foreign_key":"admin_group_id"}]');


--
-- Name: admin_groups admin_groups_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER admin_groups_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: admin_permissions admin_permissions_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER admin_permissions_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.admin_permissions FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: admins admins_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER admins_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.admins FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: analytics_cache analytics_cache_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER analytics_cache_stamp_record BEFORE UPDATE ON api_umbrella.analytics_cache FOR EACH ROW EXECUTE FUNCTION api_umbrella.update_timestamp();


--
-- Name: analytics_cache analytics_cache_unique_user_ids; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER analytics_cache_unique_user_ids BEFORE INSERT OR UPDATE OF data ON api_umbrella.analytics_cache FOR EACH ROW EXECUTE FUNCTION api_umbrella.analytics_cache_extract_unique_user_ids();


--
-- Name: analytics_cities analytics_cities_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER analytics_cities_stamp_record BEFORE UPDATE ON api_umbrella.analytics_cities FOR EACH ROW EXECUTE FUNCTION api_umbrella.update_timestamp();


--
-- Name: api_backend_http_headers api_backend_http_headers_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backend_http_headers_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_http_headers FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backend_settings","primary_key":"id","foreign_key":"api_backend_settings_id"}]');


--
-- Name: api_backend_rewrites api_backend_rewrites_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backend_rewrites_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_rewrites FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backends","primary_key":"id","foreign_key":"api_backend_id"}]');


--
-- Name: api_backend_servers api_backend_servers_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backend_servers_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_servers FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backends","primary_key":"id","foreign_key":"api_backend_id"}]');


--
-- Name: api_backend_settings_required_roles api_backend_settings_required_roles_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backend_settings_required_roles_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_settings_required_roles FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backend_settings","primary_key":"id","foreign_key":"api_backend_settings_id"}]');


--
-- Name: api_backend_settings api_backend_settings_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backend_settings_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_settings FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backends","primary_key":"id","foreign_key":"api_backend_id"},{"table_name":"api_backend_sub_url_settings","primary_key":"id","foreign_key":"api_backend_sub_url_settings_id"}]');


--
-- Name: api_backend_sub_url_settings api_backend_sub_url_settings_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backend_sub_url_settings_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_sub_url_settings FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backends","primary_key":"id","foreign_key":"api_backend_id"}]');


--
-- Name: api_backend_url_matches api_backend_url_matches_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backend_url_matches_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_url_matches FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backends","primary_key":"id","foreign_key":"api_backend_id"}]');


--
-- Name: api_backends api_backends_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_backends_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_backends FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: api_roles api_roles_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_roles_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_roles FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: api_scopes api_scopes_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_scopes_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_scopes FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: api_user_settings api_user_settings_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_user_settings_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_user_settings FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_users","primary_key":"id","foreign_key":"api_user_id"}]');


--
-- Name: api_users api_users_cache_api_role_ids_trigger; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_cache_api_role_ids_trigger BEFORE INSERT OR UPDATE ON api_umbrella.api_users FOR EACH ROW EXECUTE FUNCTION api_umbrella.api_users_cache_api_role_ids_trigger();


--
-- Name: api_users api_users_increment_version_trigger; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_increment_version_trigger BEFORE INSERT OR UPDATE ON api_umbrella.api_users FOR EACH ROW EXECUTE FUNCTION api_umbrella.api_users_increment_version();


--
-- Name: api_users_roles api_users_roles_cache_api_role_ids_delete_trigger; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_roles_cache_api_role_ids_delete_trigger AFTER DELETE ON api_umbrella.api_users_roles REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION api_umbrella.api_users_roles_cache_api_role_ids_trigger();


--
-- Name: api_users_roles api_users_roles_cache_api_role_ids_insert_trigger; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_roles_cache_api_role_ids_insert_trigger AFTER INSERT ON api_umbrella.api_users_roles REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION api_umbrella.api_users_roles_cache_api_role_ids_trigger();


--
-- Name: api_users_roles api_users_roles_cache_api_role_ids_truncate_trigger; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_roles_cache_api_role_ids_truncate_trigger AFTER TRUNCATE ON api_umbrella.api_users_roles FOR EACH STATEMENT EXECUTE FUNCTION api_umbrella.api_users_roles_cache_api_role_ids_trigger();


--
-- Name: api_users_roles api_users_roles_cache_api_role_ids_update_trigger; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_roles_cache_api_role_ids_update_trigger AFTER UPDATE ON api_umbrella.api_users_roles REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION api_umbrella.api_users_roles_cache_api_role_ids_trigger();


--
-- Name: api_users_roles api_users_roles_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_roles_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_users_roles FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_users","primary_key":"id","foreign_key":"api_user_id"}]');


--
-- Name: api_users api_users_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER api_users_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.api_users FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: admin_groups audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_groups_admin_permissions audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups_admin_permissions FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_groups_admins audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups_admins FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_groups_api_scopes audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.admin_groups_api_scopes FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_permissions audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.admin_permissions FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admins audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.admins FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_http_headers audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_http_headers FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_rewrites audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_rewrites FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_servers audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_servers FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_settings audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_settings FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_settings_required_roles audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_settings_required_roles FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_sub_url_settings audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_sub_url_settings FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_url_matches audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backend_url_matches FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backends audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_backends FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_roles audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_roles FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_scopes audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_scopes FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_user_settings audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_user_settings FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_users audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_users FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_users_roles audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.api_users_roles FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: published_config audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.published_config FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: rate_limits audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.rate_limits FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: website_backends audit_trigger_row; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_row AFTER INSERT OR DELETE OR UPDATE ON api_umbrella.website_backends FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_groups audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.admin_groups FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_groups_admin_permissions audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.admin_groups_admin_permissions FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_groups_admins audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.admin_groups_admins FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_groups_api_scopes audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.admin_groups_api_scopes FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admin_permissions audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.admin_permissions FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: admins audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.admins FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_http_headers audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backend_http_headers FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_rewrites audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backend_rewrites FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_servers audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backend_servers FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_settings audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backend_settings FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_settings_required_roles audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backend_settings_required_roles FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_sub_url_settings audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backend_sub_url_settings FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backend_url_matches audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backend_url_matches FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_backends audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_backends FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_roles audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_roles FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_scopes audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_scopes FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_user_settings audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_user_settings FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_users audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_users FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: api_users_roles audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.api_users_roles FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: published_config audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.published_config FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: rate_limits audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.rate_limits FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: website_backends audit_trigger_stm; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER audit_trigger_stm AFTER TRUNCATE ON api_umbrella.website_backends FOR EACH STATEMENT EXECUTE FUNCTION audit.if_modified_func('true');


--
-- Name: cache cache_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER cache_stamp_record BEFORE UPDATE ON api_umbrella.cache FOR EACH ROW EXECUTE FUNCTION api_umbrella.update_timestamp();


--
-- Name: distributed_rate_limit_counters distributed_rate_limit_counters_increment_version_trigger; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER distributed_rate_limit_counters_increment_version_trigger BEFORE INSERT OR UPDATE ON api_umbrella.distributed_rate_limit_counters FOR EACH ROW EXECUTE FUNCTION api_umbrella.distributed_rate_limit_counters_increment_version();


--
-- Name: published_config published_config_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER published_config_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.published_config FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: rate_limits rate_limits_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER rate_limits_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.rate_limits FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record('[{"table_name":"api_backend_settings","primary_key":"id","foreign_key":"api_backend_settings_id"},{"table_name":"api_user_settings","primary_key":"id","foreign_key":"api_user_settings_id"}]');


--
-- Name: website_backends website_backends_stamp_record; Type: TRIGGER; Schema: api_umbrella; Owner: -
--

CREATE TRIGGER website_backends_stamp_record BEFORE INSERT OR DELETE OR UPDATE ON api_umbrella.website_backends FOR EACH ROW EXECUTE FUNCTION api_umbrella.stamp_record();


--
-- Name: admin_groups_admin_permissions admin_groups_admin_permissions_admin_group_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_admin_permissions
    ADD CONSTRAINT admin_groups_admin_permissions_admin_group_id_fkey FOREIGN KEY (admin_group_id) REFERENCES api_umbrella.admin_groups(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: admin_groups_admin_permissions admin_groups_admin_permissions_admin_permission_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_admin_permissions
    ADD CONSTRAINT admin_groups_admin_permissions_admin_permission_id_fkey FOREIGN KEY (admin_permission_id) REFERENCES api_umbrella.admin_permissions(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: admin_groups_admins admin_groups_admins_admin_group_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_admins
    ADD CONSTRAINT admin_groups_admins_admin_group_id_fkey FOREIGN KEY (admin_group_id) REFERENCES api_umbrella.admin_groups(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: admin_groups_admins admin_groups_admins_admin_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_admins
    ADD CONSTRAINT admin_groups_admins_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES api_umbrella.admins(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: admin_groups_api_scopes admin_groups_api_scopes_admin_group_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_api_scopes
    ADD CONSTRAINT admin_groups_api_scopes_admin_group_id_fkey FOREIGN KEY (admin_group_id) REFERENCES api_umbrella.admin_groups(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: admin_groups_api_scopes admin_groups_api_scopes_api_scope_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.admin_groups_api_scopes
    ADD CONSTRAINT admin_groups_api_scopes_api_scope_id_fkey FOREIGN KEY (api_scope_id) REFERENCES api_umbrella.api_scopes(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_http_headers api_backend_http_headers_api_backend_settings_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_http_headers
    ADD CONSTRAINT api_backend_http_headers_api_backend_settings_id_fkey FOREIGN KEY (api_backend_settings_id) REFERENCES api_umbrella.api_backend_settings(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_rewrites api_backend_rewrites_api_backend_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_rewrites
    ADD CONSTRAINT api_backend_rewrites_api_backend_id_fkey FOREIGN KEY (api_backend_id) REFERENCES api_umbrella.api_backends(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_servers api_backend_servers_api_backend_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_servers
    ADD CONSTRAINT api_backend_servers_api_backend_id_fkey FOREIGN KEY (api_backend_id) REFERENCES api_umbrella.api_backends(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_settings api_backend_settings_api_backend_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_settings
    ADD CONSTRAINT api_backend_settings_api_backend_id_fkey FOREIGN KEY (api_backend_id) REFERENCES api_umbrella.api_backends(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_settings api_backend_settings_api_backend_sub_url_settings_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_settings
    ADD CONSTRAINT api_backend_settings_api_backend_sub_url_settings_id_fkey FOREIGN KEY (api_backend_sub_url_settings_id) REFERENCES api_umbrella.api_backend_sub_url_settings(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_settings_required_roles api_backend_settings_required_role_api_backend_settings_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_settings_required_roles
    ADD CONSTRAINT api_backend_settings_required_role_api_backend_settings_id_fkey FOREIGN KEY (api_backend_settings_id) REFERENCES api_umbrella.api_backend_settings(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_settings_required_roles api_backend_settings_required_roles_api_role_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_settings_required_roles
    ADD CONSTRAINT api_backend_settings_required_roles_api_role_id_fkey FOREIGN KEY (api_role_id) REFERENCES api_umbrella.api_roles(id) DEFERRABLE;


--
-- Name: api_backend_sub_url_settings api_backend_sub_url_settings_api_backend_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_sub_url_settings
    ADD CONSTRAINT api_backend_sub_url_settings_api_backend_id_fkey FOREIGN KEY (api_backend_id) REFERENCES api_umbrella.api_backends(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_backend_url_matches api_backend_url_matches_api_backend_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_backend_url_matches
    ADD CONSTRAINT api_backend_url_matches_api_backend_id_fkey FOREIGN KEY (api_backend_id) REFERENCES api_umbrella.api_backends(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_user_settings api_user_settings_api_user_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_user_settings
    ADD CONSTRAINT api_user_settings_api_user_id_fkey FOREIGN KEY (api_user_id) REFERENCES api_umbrella.api_users(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: api_users api_users_registration_key_creator_api_user_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_users
    ADD CONSTRAINT api_users_registration_key_creator_api_user_id_fkey FOREIGN KEY (registration_key_creator_api_user_id) REFERENCES api_umbrella.api_users(id) ON DELETE RESTRICT;


--
-- Name: api_users_roles api_users_roles_api_role_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_users_roles
    ADD CONSTRAINT api_users_roles_api_role_id_fkey FOREIGN KEY (api_role_id) REFERENCES api_umbrella.api_roles(id) DEFERRABLE;


--
-- Name: api_users_roles api_users_roles_api_user_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.api_users_roles
    ADD CONSTRAINT api_users_roles_api_user_id_fkey FOREIGN KEY (api_user_id) REFERENCES api_umbrella.api_users(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: rate_limits rate_limits_api_backend_settings_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.rate_limits
    ADD CONSTRAINT rate_limits_api_backend_settings_id_fkey FOREIGN KEY (api_backend_settings_id) REFERENCES api_umbrella.api_backend_settings(id) ON DELETE CASCADE DEFERRABLE;


--
-- Name: rate_limits rate_limits_api_user_settings_id_fkey; Type: FK CONSTRAINT; Schema: api_umbrella; Owner: -
--

ALTER TABLE ONLY api_umbrella.rate_limits
    ADD CONSTRAINT rate_limits_api_user_settings_id_fkey FOREIGN KEY (api_user_settings_id) REFERENCES api_umbrella.api_user_settings(id) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--


INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1498350289');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1554823736');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1560722058');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1560888068');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1595106665');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1596759299');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1635022846');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1645733075');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1647916501');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1651280172');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1699559596');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1699559696');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1699650325');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1700281762');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1700346585');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1701483732');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1721347955');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1738353016');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1753472899');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1769633747');
INSERT INTO api_umbrella.lapis_migrations (name) VALUES ('1769732670');

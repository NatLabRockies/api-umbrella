# Clean the database using deletion.
#
# We can't use transactions, since we rely on the data we insert in the tests
# being available to the remote test server, which won't share the transaction.
#
# We use deletion instead of truncation, since it seems to perform better for
# our specific use-cases. We also need to be careful to preserve sequence IDs
# due to our polling logic (eg, polling for published_configs changes).
#
# We previously used the database_cleaner gem, but we've hit some bugs
# (https://github.com/DatabaseCleaner/database_cleaner-active_record/issues/62),
# and can further optimize using a custom approach
# (https://github.com/DatabaseCleaner/database_cleaner-active_record/issues/26).
class DatabaseDeleter
  class SuperuserConnection < ActiveRecord::Base
    self.abstract_class = true
  end

  def self.connection
    # Use a superuser connection so we can set the session_replication_role.
    @connection ||= begin
      SuperuserConnection.establish_connection({
        :adapter => "postgresql",
        :host => $config["postgresql"]["host"],
        :port => $config["postgresql"]["port"],
        :database => $config["postgresql"]["database"],
        :username => "postgres",
        :password => "dev_password",
        :schema_search_path => "api_umbrella, public",
        :variables => {
          "timezone" => "UTC",
          "audit.application_name" => "test_app_name",
          "audit.application_user_id" => "00000000-1111-2222-3333-444444444444",
          "audit.application_user_name" => "test_example_admin_username",
        },
      })

      SuperuserConnection.connection
    end
  end

  def self.tables
    @tables ||= begin
      tables = connection.select_values("SELECT quote_ident(schemaname) || '.' || quote_ident(tablename) FROM pg_catalog.pg_tables WHERE schemaname IN ('api_umbrella', 'audit')")

      tables -= [
        # Don't truncate the Lapis migrations table.
        "api_umbrella.lapis_migrations",

        # Don't truncate the API users table (or the associated relationships),
        # since we want to keep seeded users between tests. We'll manually clear
        # non-seeded records.
        "api_umbrella.api_users",
        "api_umbrella.api_users_roles",
        "api_umbrella.api_user_settings",
        "api_umbrella.api_roles",
        "api_umbrella.rate_limits",

        # Don't truncate the admin permissions table, since it's a static list of
        # seeded values.
        "api_umbrella.admin_permissions",

        # Don't clean the published config between tests, since we might be
        # altering it in some tests that call "prepend_api_backends" inside
        # "once_per_class_setup," which assumes that the published config will then
        # stick around for all the tests in the class (rather than being cleared
        # before each individual test).
        "api_umbrella.published_config",

        # Don't truncate the table of cached city locations from geoip results.
        # Since these cached values are only inserted if the nginx processes
        # haven't seen the city before (and not inserted if it's in the in-memory
        # cache), truncating this table in the middle of runs may lead to
        # unexpected results (since data will then be missing from the table that
        # the in-memory cache thinks should be there).
        "api_umbrella.analytics_cities",
      ]

      tables
    end
  end

  def self.clean
    delete_sql = [
      "BEGIN",

      # Optimize delete performance by disabling all triggers, to avoid some of
      # our auditing trigger overhead.
      # https://github.com/DatabaseCleaner/database_cleaner-active_record/issues/26
      "SET session_replication_role = replica",
    ]

    delete_sql += tables.map do |table_name|
      "DELETE FROM #{connection.quote_table_name(table_name)}"
    end

    delete_sql += [
      # Manually delete all the non-seeded users and roles that are now unused.
      "DELETE FROM api_users WHERE registration_source IS NULL OR registration_source != 'seed'",
      "DELETE FROM api_roles WHERE api_roles.id IN (SELECT api_roles.id FROM api_roles LEFT JOIN api_users_roles ON api_roles.id = api_users_roles.api_role_id LEFT JOIN api_backend_settings_required_roles ON api_roles.id = api_backend_settings_required_roles.api_role_id WHERE api_users_roles.api_user_id IS NULL AND api_backend_settings_required_roles.api_backend_settings_id IS NULL)",

      "SET session_replication_role = DEFAULT",
      "COMMIT",
    ]

    connection.execute(delete_sql.join("; "))
  end
end

# ActiveRecord::Base.logger = Logger.new(STDOUT)

# Clean the database after each test.
class Minitest::Test
  def setup
    # If tests are being run in parallel, disable database cleaner between test
    # runs, since parallel tests should not reset their state between runs
    # (doing so might interfere with the other parallel tests running).
    if(self.class.run_order != :parallel && $config)
      DatabaseDeleter.clean
    end

    super
  end
end

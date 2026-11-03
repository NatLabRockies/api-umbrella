require "English"
require "ipaddr"
require "support/api_umbrella_test_helpers/admin_auth"
require "support/api_umbrella_test_helpers/common_asserts"
require "support/api_umbrella_test_helpers/shell"

module ApiUmbrellaTestHelpers
  module Setup
    extend ActiveSupport::Concern

    include ApiUmbrellaTestHelpers::AdminAuth
    include ApiUmbrellaTestHelpers::CommonAsserts
    include ApiUmbrellaTestHelpers::Shell

    @@incrementing_unique_number = 0
    @@incrementing_unique_ip_addr = IPAddr.new("127.0.0.1")
    @@file_config_version = 1
    @@current_override_config = {}
    mattr_reader :api_user
    mattr_reader :api_key
    mattr_reader :http_options
    mattr_reader :keyless_http_options
    mattr_accessor :api_umbrella_process
    mattr_accessor :start_complete
    mattr_accessor :setup_complete
    mattr_accessor :setup_config_version_complete
    mattr_accessor :setup_api_user_complete
    mattr_accessor(:setup_lock) { Monitor.new }
    mattr_accessor(:config_lock) { Monitor.new }
    mattr_accessor(:config_set_lock) { Monitor.new }
    mattr_accessor(:config_publish_lock) { Monitor.new }
    mattr_accessor(:increment_lock) { Monitor.new }

    included do
      mattr_accessor :unique_test_class_id_value
      mattr_accessor :unique_test_class_hostname_value
      mattr_accessor :class_setup_complete
      mattr_accessor(:class_setup_lock) { Monitor.new }
    end

    # Start the API Umbrella server process before any tests run.
    #
    # We perform this before the #run phase (rather than in the more normal
    # #setup phase) so that the time spent starting up doesn't get counted as
    # part of the first test being run (which would skew the metrics for
    # individual test times). This also occurs later than directly inside
    # test_helper.rb so that we're sure minitest will actually run (for
    # example, no invalid command line flags given) and this includes the
    # startup time in the overall test times (just not any individual test
    # times).
    def run
      self.setup_lock.synchronize do
        unless self.start_complete
          # Start the API Umbrella process to test against.
          self.api_umbrella_process = ApiUmbrellaTestHelpers::Process.instance
          self.api_umbrella_process.start
          self.start_complete = true

          ActiveRecord::Base.establish_connection({
            :adapter => "postgresql",
            :encoding => "unicode",
            :host => $config["postgresql"]["host"],
            :port => $config["postgresql"]["port"],
            :database => $config["postgresql"]["database"],
            :username => $config["postgresql"]["migrations"]["username"],
            :password => $config["postgresql"]["migrations"]["password"],
            :pool => 50,
            :schema_search_path => "api_umbrella, public",
            :variables => {
              "timezone" => "UTC",
              "audit.application_name" => "test_app_name",
              "audit.application_user_id" => "00000000-1111-2222-3333-444444444444",
              "audit.application_user_name" => "test_example_admin_username",
            },
          })
        end
      end

      super
    end

    private

    def setup_server
      self.setup_lock.synchronize do
        unless self.setup_complete
          require "faraday/typhoeus"
          client = OpenSearch::Client.new({
            :adapter => :typhoeus,
            :hosts => $config["opensearch"]["hosts"],
            :retry_on_failure => 5,
            :retry_on_status => [503],
          })
          LogItem.client = client

          # Wipe opensearch indices before beginning.
          #
          # We completely delete the indices here (rather than relying on
          # LogItem.clean_indices!), so that we're sure each test gets fresh
          # index template and mappings setup.
          client.perform_request "DELETE", "_data_stream/api-umbrella-test-*"
          client.indices.delete :index => "api-umbrella-test-*"

          self.setup_complete = true
        end

        unless self.setup_api_user_complete
          user = FactoryBot.create(:api_user, {
            :registration_source => "seed",
            :settings => FactoryBot.build(:api_user_settings, {
              :rate_limit_mode => "unlimited",
            }),
          })

          @@api_user = user
          @@api_key = user.api_key
          assert(@@api_key)
          @@http_options = {
            # Disable SSL verification by default, since most of our tests are
            # against our self-signed SSL certificate for the test environment.
            :ssl_verifypeer => false,
            :ssl_verifyhost => 0,

            # When sending x-www-form-urlencoded encoded bodies, serialize Ruby
            # arrays the way Rails expects
            # (https://github.com/typhoeus/ethon/pull/104).
            :params_encoding => :rack,

            :headers => {
              "X-Api-Key" => @@api_key,
            }.freeze,
          }.freeze
          @@keyless_http_options = @@http_options.except(:headers).freeze

          self.setup_api_user_complete = true
        end

        unless self.setup_config_version_complete
          publish_default_config_version
          self.setup_config_version_complete = true
        end
      end
    end

    def publish_default_config_version
      PublishedConfig.delete_all
      PublishedConfig.create!(:config => {})
      PublishedConfig.active.wait_until_live
    end

    # If tests need to delete all the ApiUser records from the database, then
    # they need to call this method after finishing so the default ApiUser
    # record will be re-created for other tests that depend on it.
    def default_api_user_needed
      ApiUmbrellaTestHelpers::Setup.setup_lock.synchronize do
        ApiUmbrellaTestHelpers::Setup.setup_api_user_complete = false
      end
    end

    def once_per_class_setup
      unless self.class_setup_complete
        self.class_setup_lock.synchronize do
          unless self.class_setup_complete
            yield
            self.class_setup_complete = true
          end
        end
      end
    end

    def prepend_api_backends(api_attributes)
      @prepend_api_backends_counter ||= 0
      api_ids = api_attributes.map! do |attributes|
        attributes.deep_symbolize_keys!

        @prepend_api_backends_counter += 1
        attributes[:name] ||= "#{unique_test_id}-#{@prepend_api_backends_counter}"
        attributes[:backend_protocol] ||= "http"
        attributes[:balance_algorithm] ||= "least_conn"

        response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/apis.json", @@http_options.deep_merge(admin_token).deep_merge({
          :headers => { "Content-Type" => "application/json" },
          :body => MultiJson.dump(:api => attributes),
        }))
        assert_response_code(201, response)
        data = MultiJson.load(response.body)

        id = data["api"]["id"]
        assert(id)

        id
      end

      publish_api_backends(api_ids)

      yield if(block_given?)
    ensure
      if(block_given? && api_ids && api_ids.any?)
        unpublish_api_backends(api_ids)
      end
    end

    def prepend_website_backends(website_attributes)
      website_ids = website_attributes.map do |attributes|
        attributes.deep_stringify_keys!
        WebsiteBackend.create!(attributes).id
      end

      publish_website_backends(website_ids)

      yield if(block_given?)
    ensure
      if(block_given? && website_ids && website_ids.any?)
        unpublish_website_backends(website_ids)
      end
    end

    def publish_api_backends(record_ids)
      publish_backends("apis", record_ids)
    end

    def publish_website_backends(record_ids)
      publish_backends("website_backends", record_ids)
    end

    # Publish backend changes for the given record IDs.
    #
    # Publishing is performed by hitting the internal publish API endpoint. We
    # do this via the API, rather than directly manipulating the
    # PublishedConfig database table, since the resulting published config is
    # dependent on how backend records get serialized into JSON during the
    # publishing process. Since the Lua models might do this differently, use
    # the real API to ensure we're testing the real publishing process, and the
    # real resulting JSON.
    def publish_backends(type, record_ids)
      self.config_publish_lock.synchronize do
        config = { type => {} }
        record_ids.each do |record_id|
          config[type][record_id] = { :publish => "1" }
        end

        response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/config/publish.json", @@http_options.deep_merge(admin_token).deep_merge({
          :headers => { "Content-Type" => "application/json" },
          :body => MultiJson.dump(:config => config),
        }))

        assert_response_code(201, response)
        PublishedConfig.active.wait_until_live
      end
    end

    def unpublish_api_backends(record_ids)
      self.config_publish_lock.synchronize do
        ApiBackend.delete(record_ids)
        publish_backends("apis", record_ids)
      end
    end

    def unpublish_website_backends(record_ids)
      self.config_publish_lock.synchronize do
        WebsiteBackend.delete(record_ids)
        publish_backends("website_backends", record_ids)
      end
    end

    # Typically we want to publish config by using the "publish_backends"
    # method, which uses the API to publish config (to better replicate what
    # will happen in the real app). But in cases where we want to explicitly
    # test invalid configuration that the app may not allow (eg, to test how
    # existing data might be handled before extra validations were added), we
    # can use this method to directly override the published config JSON.
    def force_publish_config
      self.config_publish_lock.synchronize do
        new_published_config = nil
        PublishedConfig.transaction do
          # Within the lock and transaction, find the current config, yield it
          # to the block to allow for modifications, and then publish the
          # resulting modified config.
          config = PublishedConfig.active_config
          new_config = yield config
          new_published_config = PublishedConfig.create!(:config => new_config)
        end

        new_published_config.wait_until_live
      end
    end

    def override_config(config, options = {})
      self.config_lock.synchronize do
        original_config = @@current_override_config.deep_dup

        begin
          override_config_set(config, options)
          yield
        ensure
          override_config_set(original_config, options)
        end
      end
    end

    def override_config_merge(config, options = {})
      self.config_lock.synchronize do
        original_config = @@current_override_config.deep_dup

        begin
          override_config_set(original_config.deep_stringify_keys.deep_merge(config.deep_stringify_keys), options)
          yield
        ensure
          override_config_set(original_config, options)
        end
      end
    end

    def override_config_set(config, options = {})
      self.config_set_lock.synchronize do
        if(self.class.run_order == :parallel)
          raise "`override_config_set` cannot be called with `parallelize_me!` in the same class. Since overriding config affects the global state, it cannot be used with parallel tests."
        end

        previous_override_config = @@current_override_config.deep_dup

        config = config.deep_stringify_keys

        @@file_config_version += 1
        config["version"] ||= @@file_config_version

        ApiUmbrellaTestHelpers::Process.instance.write_test_config(config)

        self.api_umbrella_process.reload
        @@current_override_config = config.deep_dup
        already_restarted_services = []
        Timeout.timeout(options.fetch(:timeout, 50)) do
          self.api_umbrella_process.wait_for_config_version("file_config_version", config["version"], config)
        rescue MultiJson::ParseError => e
          # If the configuration changes involve changes to the
          # "active_config" shdict size, then this can result in the API
          # configuration being temporarily unpublished during reloads. In
          # these cases, the publishing process may temporarily throw errors,
          # since the "state" and "health" endpoints may temporarily go
          # missing. So in these cases, retry and wait for the configuration
          # publishing to take effect again.
          #
          # Same goes for changing the communication scheme between http and and
          # https for the Trafficserver to Envoy communication. But this isn't a
          # change we normally expect to happen live, so we'll retry.
          if(
            previous_override_config.dig("nginx", "shared_dicts", "active_config") ||
            @@current_override_config.dig("nginx", "shared_dicts", "active_config")
          )
            sleep 0.1
            retry
          elsif previous_override_config.dig("envoy", "scheme") || @@current_override_config.dig("envoy", "scheme")
            # For http to https changes, we may also need to restart
            # trafficserver earlier than the rest of the restarts below, since
            # without this, the Traffic Server "reload" picks up the
            # requirements for the new cert, but won't pick up the actual CA
            # file changes until a full restart, leading to invalid cert errors
            # for the health checks used during the reload until a full restart
            # is performed.
            already_restarted_services += self.api_umbrella_process.restart_services(["envoy", "trafficserver"] - already_restarted_services, options)
            sleep 0.1
            retry
          else
            raise e
          end
        end

        # If trying to test what would happen to output to the "console" output
        # (instead of log files), we need to be a little careful for a few
        # reasons and cleanup and restart extra things, since this is not a
        # change we would normally expect to happen without a full restart.
        if previous_override_config.dig("log", "destination") ||
            @@current_override_config.dig("log", "destination")

          # These log files are symlinked to stdout or stderr by the perp init
          # scripts, so when switching between these log destinations, we need
          # to make sure to clean these up when testing different approaches,
          # since otherwise it might leave symlinked files in place when
          # switching back to file output, which would lead to the output going
          # to unexpected places.
          FileUtils.rm_f(File.join($config["log_dir"], "nginx-web-app/access.log"))
          FileUtils.rm_f(File.join($config["log_dir"], "nginx/access.log"))

          # Do a full restart of the affected services to ensure they pick up
          # these changes. However, note that this may still not be a great
          # test of console output, since perp will continue to output "stdout"
          # and "stderr" of the processes to the "current" log file. That's not
          # how it would behave if things were more fully restarted, but I
          # think it suffices for testing the differences in the test
          # environment for now.
          already_restarted_services += self.api_umbrella_process.restart_services([
            "fluent-bit",
            "nginx",
            "nginx-web-app",
            "trafficserver",
          ] - already_restarted_services, options)
        end

        # Restart trafficserver when changing the configuration settings that
        # require a full trafficserver restart.
        if(
          previous_override_config["strip_response_cookies"] ||
          @@current_override_config["strip_response_cookies"] ||
          previous_override_config.dig("nginx", "proxy_connect_timeout") ||
          @@current_override_config.dig("nginx", "proxy_connect_timeout") ||
          previous_override_config.dig("nginx", "proxy_read_timeout") ||
          @@current_override_config.dig("nginx", "proxy_read_timeout") ||
          previous_override_config.dig("nginx", "proxy_send_timeout") ||
          @@current_override_config.dig("nginx", "proxy_send_timeout") ||
          previous_override_config.dig("trafficserver", "records", "http", "keep_alive_no_activity_timeout_out") ||
          @@current_override_config.dig("trafficserver", "records", "http", "keep_alive_no_activity_timeout_out")
        )
          already_restarted_services += self.api_umbrella_process.restart_services(["trafficserver", "envoy", "nginx"] - already_restarted_services, options)
        end

        if previous_override_config.dig("envoy", "scheme") ||
            @@current_override_config.dig("envoy", "scheme")
          already_restarted_services += self.api_umbrella_process.restart_services(["envoy", "trafficserver"] - already_restarted_services, options)
        end

        if previous_override_config["http_proxy"] ||
            @@current_override_config["http_proxy"] ||
            previous_override_config["https_proxy"] ||
            @@current_override_config["https_proxy"]

          already_restarted_services += self.api_umbrella_process.restart_services(["fluent-bit"] - already_restarted_services, options)
        end
      end
    end

    def override_config_reset(options = {})
      override_config_set({}, options)
    end

    def to_unique_id(name)
      name.gsub(/[^\w]+/, "-")
    end

    def to_unique_hostname(name)
      # Replace all non alpha-numeric chars (namely underscores that might be
      # in the ID) with dashes (since underscores aren't valid for hostnames).
      hostname = name.downcase.gsub(/[^a-z0-9]+/, "-")

      # Truncate the hostname so the label will fit in unbound's 63 char limit.
      hostname = hostname[-56..] || hostname

      # Strip first char if it happens to be a dash.
      hostname.gsub!(/^-/, "")

      # Since we've truncated the test ID, it's possible it's no longer unique,
      # so append a unique number to the end (ensuring that it will fit within
      # the 63 char limit).
      unique_number = next_unique_number
      assert_operator(unique_number, :<=, 999999)
      "#{hostname}-#{unique_number.to_s.rjust(6, "0")}"
    end

    def unique_test_class_id
      self.unique_test_class_id_value ||= to_unique_id(self.class.name)
    end

    def unique_test_class_hostname
      self.unique_test_class_hostname_value ||= to_unique_hostname(unique_test_class_id)
    end

    def unique_test_id
      @unique_test_id ||= to_unique_id("#{self.class.name}##{self.name}")
    end

    def unique_test_subdomain
      @unique_test_subdomain ||= to_unique_hostname(unique_test_id)
    end

    def unique_test_hostname
      @unique_test_hostname ||= "#{unique_test_subdomain}.test"
    end

    def next_unique_number
      self.increment_lock.synchronize do
        @@incrementing_unique_number += 1
        @@incrementing_unique_number
      end
    end

    def next_unique_ip_addr
      self.increment_lock.synchronize do
        @@incrementing_unique_ip_addr = @@incrementing_unique_ip_addr.succ
        @@incrementing_unique_ip_addr.to_s
      end
    end

    def unique_test_ip_addr
      @unique_test_ip_addr ||= next_unique_ip_addr
    end

    # Typheous/Ethon doesn't currently support sending empty HTTP headers by
    # simply setting the value to an empty string:
    # https://github.com/typhoeus/ethon/pull/132
    #
    # This provides a workaround by using a fake extra header (see
    # https://curl.haxx.se/mail/lib-2010-08/0174.html).
    #
    # If the Ethon pull request gets merged in, we can perhaps remove this, but
    # we may still need it if we want our test suite to run on CentOS 6 (where
    # curl is at v7.19, lacking the official support for sending empty values).
    def empty_http_header_options(header)
      @empty_http_header_counter ||= 0
      @empty_http_header_counter += 1
      {
        :headers => {
          # First set the header to null to prevent Typheous from adding some
          # default headers back in (like Content-Type).
          header => nil,

          # Next, add a fake header, and in the content of the header add line
          # breaks and the real header without a value.
          "X-Empty-Http-Header-Curl-Workaround#{@empty_http_header_counter}" => "ignore\r\n#{header}:",
        },
      }
    end
  end
end

require "capybara/minitest"
require "capybara/shadowdom"
require "capybara-screenshot/minitest"
require "open3"
require "support/api_umbrella_test_helpers/admin_auth"
require "support/api_umbrella_test_helpers/capybara_codemirror"
require "support/api_umbrella_test_helpers/capybara_custom_bootstrap_inputs"
require "support/api_umbrella_test_helpers/capybara_selectize"
require "support/api_umbrella_test_helpers/downloads"
require "support/api_umbrella_test_helpers/process"

def capybara_register_driver(driver_name, options = {})
  Capybara.register_driver(driver_name) do |app|
    root_dir = File.join(ApiUmbrellaTestHelpers::Process::TEST_RUN_ROOT, "capybara")
    FileUtils.mkdir_p(root_dir)

    driver_options = Selenium::WebDriver::Chrome::Options.new.tap do |opts|
      opts.add_argument "--headless=new"

      # Allow connections to our self-signed SSL localhost test server.
      opts.add_argument "--allow-insecure-localhost"

      # Use /tmp instead of /dev/shm for Docker environments where /dev/shm is
      # too small:
      # https://github.com/GoogleChrome/puppeteer/blob/v1.10.0/docs/troubleshooting.md#tips
      opts.add_argument "--disable-dev-shm-usage"

      # Use a static user agent for some session tests.
      opts.add_argument "--user-agent=#{ApiUmbrellaTestHelpers::AdminAuth::STATIC_USER_AGENT}"

      # Allow for usage in Docker.
      opts.add_argument "--no-sandbox"

      # Set the Accept-Language header used in tests.
      if options[:lang]
        opts.add_argument "--accept-lang=#{options[:lang]}"
      end

      # Set download path for Chrome >= 77
      opts.add_preference(:download, :default_directory => ApiUmbrellaTestHelpers::Downloads::DOWNLOADS_ROOT)

      # Enable web socket support for BiDi log support below.
      opts.web_socket_url = true

      # Do not auto-accept alerts/dialogs so that beforeUnload alerts can be
      # tested: https://issues.chromium.org/issues/351858989#comment28
      opts.unhandled_prompt_behavior = "ignore"
    end

    service = Selenium::WebDriver::Chrome::Service.new.tap do |opts|
      opts.args = [
        "--log_path=#{File.join(root_dir, "#{driver_name}.log")}",
        "--verbose",
      ]
    end

    driver = Capybara::Selenium::Driver.new(app, browser: :chrome, options: driver_options, service: service)
    driver.resize_window_to(driver.current_window_handle, 1024, 4000)

    # Keep track of console log output so we can warn/error depending on
    # severity of JavaScript logs.
    #
    # Like https://github.com/dbalatero/capybara-chromedriver-logger, but without
    # Selenium 4 issues
    # (https://github.com/dbalatero/capybara-chromedriver-logger/issues/34), and
    # compatible with GeckoDriver.
    driver.browser.script.add_console_message_handler do |log|
      # Store the logs on a global (this might not be ideal, but Thread.current
      # doesn't seem to work and this does).
      $selenium_logs ||= [] # rubocop:disable Style/GlobalVars
      $selenium_logs << log # rubocop:disable Style/GlobalVars

      # Print out any console output (regardless of log level) to the screen for
      # better awareness and debugging.
      warn "#{Rainbow("JavaScript [#{log.level}]:").color(:yellow).bright} #{log.text}\n    #{Rainbow(log.inspect).color(:silver)}"
    end
    # Throw immediate error if uncaught javascript error is encountered (not
    # just a `console.error` that above would handle).
    driver.browser.script.add_javascript_error_handler do |log|
      warn "#{Rainbow("JavaScript [#{log.level}]:").color(:red).bright} #{log.text}\n    #{Rainbow(log.inspect).color(:silver)}"
      raise "Uncaught JavaScript exception: #{log.text}"
    end

    driver
  end

  Capybara::Screenshot.register_driver(driver_name) do |driver, path|
    # Chrome doesn't support Selenium's `full_page: true` option for
    # `save_screenshot`, so manually resize the page to the content.
    width = driver.execute_script("return Math.max(document.body.scrollWidth, document.body.offsetWidth, document.documentElement.clientWidth, document.documentElement.scrollWidth, document.documentElement.offsetWidth);") + 100
    width = 1024 if width < 1024
    height = driver.execute_script("return Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.clientHeight, document.documentElement.scrollHeight, document.documentElement.offsetHeight);") + 100
    height = 768 if height < 768
    driver.resize_window_to(driver.current_window_handle, width, height)

    driver.browser.save_screenshot(path)
  end
end

capybara_register_driver(:selenium_chromium_headless)
Capybara.default_driver = :selenium_chromium_headless
Capybara.default_max_wait_time = 5
Capybara.run_server = false
Capybara.app_host = "https://127.0.0.1:9081"
Capybara.save_path = File.join(API_UMBRELLA_SRC_ROOT, "test/tmp/artifacts/capybara")

# Since we're using custom styled checkboxes and radios, the actual inputs
# aren't visible. So enable this option so that Capybara will fallback to
# searching and clicking on the label for the associated checkbox when calling
# "check" and "uncheck".
Capybara.automatic_label_click = true

# Attempted workaround for "fill_in" sometimes not clearing existing input:
# https://github.com/teamcapybara/capybara/issues/2419#issuecomment-738798878
#
# This seems to crop up most frequently with the
# Test::AdminUi::TestApis#test_form test not properly clearing the "Frontend
# Host" field, so we end up with both the default value 127.0.0.1 plus the new
# value, of api.foo.com all in one string ("127.0.0.1api.foo.com").
Capybara.default_set_options = { :clear => :backspace }

Capybara::Screenshot.prune_strategy = :keep_last_run

module Minitest
  module Capybara
    class Test < Minitest::Test
      include ::Capybara::DSL
      include ::Capybara::Minitest::Assertions
      include ApiUmbrellaTestHelpers::CapybaraCodemirror
      include ApiUmbrellaTestHelpers::CapybaraCustomBootstrapInputs
      include ApiUmbrellaTestHelpers::CapybaraSelectize

      def setup
        super

        # Reset logs
        $selenium_logs = [] # rubocop:disable Style/GlobalVars
      end

      def teardown
        super

        # Clear the session and logout after each test.
        begin
          ::Capybara.reset_sessions!
        rescue
          # Resetting may fail since it navigates away from the page, which may
          # trigger an extra `onbeforeunload` alert warning. Since this is not
          # automatically handled (due to `unhandled_prompt_behavior`), trigger
          # the internal mechanism to dismiss these unload alerts, and then try
          # resetting again.
          ::Capybara.current_session.driver.send(:accept_unhandled_reset_alert)
          retry
        end

        # Ensure the default driver is used again for future tests (for any
        # tests that may have changed the driver).
        ::Capybara.use_default_driver

        # Inspect the gathered logs and fail if there are any error level logs.
        error_logs = $selenium_logs.filter { |log| log.level == "error" } # rubocop:disable Style/GlobalVars
        # Fail tests if JavaScript errors were generated during the tests.
        assert_equal([], error_logs)

        # Reset logs
        $selenium_logs = [] # rubocop:disable Style/GlobalVars
      end
    end
  end
end

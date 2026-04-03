# While not ideal, retry certain flaky tests in CI.
if ENV["CI"] == "true"
  require "minitest/retry"

  module Minitest::Retry
    # Instead of relying on minitest-retry's various built-in options (like
    # `exceptions_to_retry` and `methods_to_retry`), override it's retry logic
    # method completely to allow for more flexibility.
    #
    # The default options are sort of all-or-nothing (eg, by defining
    # `methods_to_retry`, that takes precedence over any other options), to
    # this allows for more granular decision making on which errors to retry.
    def self.failure_to_retry?(failures = [], klass_method_name, klass)
      return false if failures.empty?

      errors = failures.map(&:error).map(&:class)

      # Retry any Selenium unknown failures anywhere, since these tend to be
      # the flakier ones out in CI.
      if errors.include?(Selenium::WebDriver::Error::UnknownError)
        return true
      end

      # Retry any failure in some specific tests that might be flaky in CI due
      # to specific timing conditions.
      case klass_method_name
      when "Test::Proxy::TestTimeoutsResponse#test_response_closes_when_chunk_delay_exceeds_read_timeout",
        "Test::Proxy::RateLimits::TestNonFrozenLimit#test_non_frozen_time_limit",
        "Test::Proxy::KeepAlive::TestServerSide#test_max_connection_age_closes_connections"
        return true
      end

      false
    end
  end

  Minitest::Retry.use!
end

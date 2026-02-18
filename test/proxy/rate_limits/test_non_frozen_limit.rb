require_relative "../../test_helper"

class Test::Proxy::RateLimits::TestNonFrozenLimit < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::RateLimits
  include Minitest::Hooks

  def setup
    super
    setup_server
    once_per_class_setup do
      override_config_set({
        :default_api_backend_settings => {
          :rate_limits => [
            {
              :duration => 1000, # 1 second
              :limit_by => "api_key",
              :limit_to => 3,
              :distributed => true,
              :response_headers => true,
            },
          ],
        },
      })
    end
  end

  def after_all
    super
    override_config_reset
  end

  # The rest of the rate limit tests use a frozen time to guarantee better
  # consistency in tests (see `rate_limit_frozen_time`). This is to test the
  # real rate limiting behavior when the time isn't frozen to verify it works
  # the same.
  #
  # We'll use a short duration to actually increase the likelihood of the
  # estimated rate limit failing so that we can verify the fact that the
  # current estimated behavior can be exceeded, but only rarely.
  def test_non_frozen_time_limit
    # Make batches of requests to verify that with enough attempts the
    # estimated limit can fail.
    exceeded_hard_limit_occurrences = 0
    batches = 300
    batches.times do |i|
      # Make the number of requests below the limit, which should always
      # work initially.
      path = "/api/hello?#{i}"
      limit = 3
      options = {
        time: false,
        api_key: create_api_key,
      }
      assert_under_rate_limit(path, limit, **options)

      # Make subsequent requests until we hit the over rate limit. Normally
      # this will happen on the next request, but if the request happens to
      # span the time buckets for the 1 second duration on this limit, then
      # it's possible the key can temporarily exceed its limit by a couple of
      # requests.
      requests_allowed_beyond_limit = 0
      loop do
        response = make_requests(path, 1, **extract_make_requests_options(options)).first
        if response.code != 200
          assert_response_code(429, response)
          break
        end
        requests_allowed_beyond_limit += 1
      end

      if requests_allowed_beyond_limit > 0
        exceeded_hard_limit_occurrences += 1

        # Verify that when exceeded, the estimated rate limit at most allows a
        # couple requests past.
        assert_operator(requests_allowed_beyond_limit, :<=, 2)
      end
    end

    # Verify that this exercise did in fact trigger the scenario where the rate
    # limit estimations allow the limit to be exceeded. Given the short time
    # duration of the limit, and the number of requests being made, this should
    # be nearly guaranteed, but if this test becomes flaky we can revisit.
    #
    # If we shift away from the current estimated rate limiting algorithm, we
    # could also remove this tests, this is mainly just trying to document/test
    # current behavior.
    assert_operator(exceeded_hard_limit_occurrences, :>=, 2)
    assert_operator(exceeded_hard_limit_occurrences, :<, batches / 2)
  end
end

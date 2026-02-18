require_relative "../../test_helper"

class Test::Proxy::RateLimits::TestDistributedRateLimits < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::RateLimits
  include Minitest::Hooks

  def setup
    super
    setup_server
    @override_config = {
      :default_api_backend_settings => {
        :rate_limits => [
          {
            :duration => 50 * 60 * 1000, # 50 minutes
            :limit_by => "api_key",
            :limit_to => 1001,
            :distributed => true,
            :response_headers => true,
          },
        ],
      },
    }
    once_per_class_setup do
      override_config_set(@override_config)

      prepend_api_backends([
        {
          :frontend_host => "127.0.0.1",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/specific/", :backend_prefix => "/" }],
          :settings => {
            :rate_limits => [
              {
                :duration => 45 * 60 * 1000, # 45 minutes
                :limit_by => "api_key",
                :limit_to => 1002,
                :distributed => true,
                :response_headers => true,
              },
            ],
          },
          :sub_settings => [
            {
              :http_method => "any",
              :regex => "^/hello/subsettings/",
              :settings => {
                :rate_limits => [
                  {
                    :duration => 48 * 60 * 1000, # 48 minutes
                    :limit_by => "api_key",
                    :limit_to => 1003,
                    :distributed => true,
                    :response_headers => true,
                  },
                ],
              },
            },
            {
              :http_method => "any",
              :regex => "^/hello/non-distributed/",
              :settings => {
                :rate_limits => [
                  {
                    :duration => 12 * 60 * 1000, # 12 minutes
                    :limit_by => "api_key",
                    :limit_to => 1004,
                    :distributed => false,
                    :response_headers => true,
                  },
                ],
              },
            },
            {
              :http_method => "any",
              :regex => "^/hello/long-duration-bucket/",
              :settings => {
                :rate_limits => [
                  {
                    :duration => 24 * 60 * 60 * 1000, # 1 day
                    :limit_by => "api_key",
                    :limit_to => 1005,
                    :distributed => true,
                    :response_headers => true,
                  },
                ],
              },
            },
            {
              :http_method => "any",
              :regex => "^/hello/short-duration-bucket/",
              :settings => {
                :rate_limits => [
                  {
                    :duration => 1 * 60 * 1000, # 1 minute
                    :limit_by => "api_key",
                    :limit_to => 1006,
                    :distributed => true,
                    :response_headers => true,
                  },
                ],
              },
            },
          ],
        },
      ])
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_sets_new_limits_to_distributed_value
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
      time: rate_limit_frozen_time,
    }

    set_distributed_count(143, **extract_set_distributed_count_options(options))
    assert_local_count("/api/hello", 143, **extract_assert_local_count_options(options))
  end

  def test_increases_existing_rate_limits_to_match_distributed_value
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
      time: rate_limit_frozen_time,
    }

    responses = make_requests("/api/hello", 75, **extract_make_requests_options(options))
    assert_response_headers(75, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(75, **extract_assert_distributed_count_options(options))
    set_distributed_count(99, **extract_set_distributed_count_options(options))
    assert_local_count("/api/hello", 99, **extract_assert_local_count_options(options))
  end

  def test_ignores_distributed_value_when_lower
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
      time: rate_limit_frozen_time,
    }

    responses = make_requests("/api/hello", 80, **extract_make_requests_options(options))
    assert_response_headers(80, responses, **extract_assert_response_headers_options(options))
    set_distributed_count(60, **extract_set_distributed_count_options(options))
    assert_local_count("/api/hello", 80, **extract_assert_local_count_options(options))
  end

  def test_syncs_local_limits_into_mongo
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
    }

    responses = make_requests("/api/hello", 27, **extract_make_requests_options(options))
    assert_response_headers(27, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(27, **extract_assert_distributed_count_options(options))
  end

  def test_sets_expected_rate_limit_record_after_requests
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
    }

    responses = make_requests("/api/hello", 27, **extract_make_requests_options(options))
    assert_response_headers(27, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(27, **extract_assert_distributed_count_options(options))
    assert_distributed_count_record(**extract_assert_distributed_count_options(options))
  end

  def test_sets_expected_rate_limit_record_when_set_from_tests
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
    }

    set_distributed_count(143, **extract_set_distributed_count_options(options))
    assert_distributed_count_record(**extract_assert_distributed_count_options(options))
  end

  def test_does_not_sync_non_distributed_limits
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1004,
    }

    responses = make_requests("/#{unique_test_class_id}/specific/hello/non-distributed/", 47, **extract_make_requests_options(options))
    assert_response_headers(47, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(0, **extract_assert_distributed_count_options(options))
  end

  def test_syncs_api_specific_limits
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1002,
    }

    responses = make_requests("/#{unique_test_class_id}/specific/hello", 133, **extract_make_requests_options(options))
    assert_response_headers(133, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(133, **extract_assert_distributed_count_options(options))
  end

  # A short duration bucket test (where the accuracy bucket is 5 seconds) helps
  # uncover issues when the requests are split across multiple buckets. While
  # still not guaranteed, we're more likely to hit requests being split across
  # a 5 second boundary, than a 1 minute boundary.
  def test_syncs_short_duration_buckets
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 1 * 60 * 1000, # 1 minute
      limit_to: 1006,
    }

    responses = make_requests("/#{unique_test_class_id}/specific/hello/short-duration-bucket/", 150, **extract_make_requests_options(options))
    assert_response_headers(150, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(150, **extract_assert_distributed_count_options(options))
  end

  def test_syncs_api_specific_subsetting_limits
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1003,
    }

    responses = make_requests("/#{unique_test_class_id}/specific/hello/subsettings/", 38, **extract_make_requests_options(options))
    assert_response_headers(38, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(38, **extract_assert_distributed_count_options(options))
  end

  def test_syncs_requests_in_past_within_bucket_time
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1005,
      time: Time.now.utc - (8 * 60 * 60), # 8 hours ago
    }

    responses = make_requests("/#{unique_test_class_id}/specific/hello/long-duration-bucket/", 4, **extract_make_requests_options(options))
    assert_response_headers(4, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(4, **extract_assert_distributed_count_options(options))
  end

  def test_does_not_sync_requests_in_past_outside_bucket_time
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1005,
      time: Time.now.utc - (48 * 60 * 60), # 48 hours ago
    }

    responses = make_requests("/#{unique_test_class_id}/specific/hello/long-duration-bucket/", 3, **extract_make_requests_options(options))
    assert_response_headers(3, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(0, **extract_assert_distributed_count_options(options))
  end

  def test_syncs_within_duration_on_reload_or_start
    time = Time.now.utc
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
    }

    options[:time] = time - (40 * 60) # 40 minutes ago
    set_distributed_count(3, **extract_set_distributed_count_options(options))

    options[:time] = time - (45 * 60) # 45 minutes ago
    set_distributed_count(97, **extract_set_distributed_count_options(options))

    options[:time] = time - (51 * 60) # 51 minutes ago
    set_distributed_count(41, **extract_set_distributed_count_options(options))

    # Trigger an nginx reload by setting new configuration. While we're not
    # technically changing the configuration, setting the config gives us an
    # easier way to wait until the nginx processes have fully reloaded before
    # proceeding (so this test doesn't interfere with other tests).
    override_config_set(@override_config) do
      options[:time] = time
      assert_local_count("/api/hello", 100, **extract_assert_local_count_options(options))
    end
  end

  def test_polls_for_distributed_changes
    options = {
      api_user: FactoryBot.create(:api_user),
      duration: 50 * 60 * 1000, # 50 minutes
      limit_to: 1001,
      time: rate_limit_frozen_time,
    }

    responses = make_requests("/api/hello", 10, **extract_make_requests_options(options))
    assert_response_headers(10, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(10, **extract_assert_distributed_count_options(options))
    assert_local_count("/api/hello", 10, **extract_assert_local_count_options(options))

    responses = make_requests("/api/hello", 10, **extract_make_requests_options(options))
    assert_response_headers(20, responses, **extract_assert_response_headers_options(options))
    assert_distributed_count(20, **extract_assert_distributed_count_options(options))
    assert_local_count("/api/hello", 20, **extract_assert_local_count_options(options))

    set_distributed_count(77, **extract_set_distributed_count_options(options))
    assert_distributed_count(77, **extract_assert_distributed_count_options(options))
    assert_local_count("/api/hello", 77, **extract_assert_local_count_options(options))
  end

  # Perform the sequence cycle tests with a couple different sequence start
  # values, to ensure the cycle happens properly regardless of whether the
  # maximum value or maximum value - 1 is actually stored in the database.
  [9223372036854775804, 9223372036854775805].each do |sequence_start_val|
    define_method("test_sequence_cycle_start_#{sequence_start_val}") do
      # Before starting, sleep and then clean the counter table again.
      #
      # While database cleaner runs before each test, we have to do this here,
      # since this table might be populated after previous tests actually
      # finish (since this table gets populated asynchronously by the
      # "distributed_rate_limit_pusher" which runs every 0.25 seconds).
      sleep 0.5
      DistributedRateLimitCounter.delete_all

      options = {
        api_user: FactoryBot.create(:api_user),
        duration: 50 * 60 * 1000, # 50 minutes
        limit_to: 1001,
        time: rate_limit_frozen_time,
      }

      begin
        # Alter the sequence so that the next value is near the boundary for
        # bigints.
        DistributedRateLimitCounter.connection.execute("ALTER SEQUENCE distributed_rate_limit_counters_version_seq RESTART WITH #{sequence_start_val}")

        # Manually set the distributed count to insert a single record.
        set_distributed_count(20, **extract_set_distributed_count_options(options))
        assert_distributed_count(20, **extract_assert_distributed_count_options(options))
        assert_local_count("/api/hello", 20, **extract_assert_local_count_options(options))

        # Check that the distributed count record matches the expected version
        # sequence values.
        assert_equal(1, DistributedRateLimitCounter.count)
        counter = DistributedRateLimitCounter.first
        assert_equal(sequence_start_val, counter.version)
        assert_equal(20, counter.value)

        # Make 1 normal request, and ensure the counts increment as expected.
        responses = make_requests("/api/hello", 1, **extract_make_requests_options(options))
        assert_response_headers(21, responses, **extract_assert_response_headers_options(options))
        assert_distributed_count(21, **extract_assert_distributed_count_options(options))
        assert_local_count("/api/hello", 21, **extract_assert_local_count_options(options))

        # Verify the distributed count record in the database is incrementing
        # the sequence as expected. Note that the sequence actually increments
        # by 2 after making a single request, since the upsert operation ends
        # up calling nextval() on the sequence twice (since trigger is execute
        # before both insert and updates, and the upsert ends up trying both).
        assert_equal(1, DistributedRateLimitCounter.count)
        counter.reload
        assert_equal(sequence_start_val + 2, counter.version)
        assert_equal(21, counter.value)

        # Make 1 more normal request
        responses = make_requests("/api/hello", 1, **extract_make_requests_options(options))
        assert_response_headers(22, responses, **extract_assert_response_headers_options(options))
        assert_distributed_count(22, **extract_assert_distributed_count_options(options))
        assert_local_count("/api/hello", 22, **extract_assert_local_count_options(options))

        # This last request should have caused the sequence to cycle to the
        # beginning negative value.
        assert_equal(1, DistributedRateLimitCounter.count)
        counter.reload
        assert_equal(-9223372036854775807 + (sequence_start_val + 4 - 9223372036854775807 - 1), counter.version)
        assert_equal(22, counter.value)

        # Set the distributed count manually and ensure that the nginx workers
        # are still polling properly to pick up new changes after the sequence
        # has cycled.
        set_distributed_count(99, **extract_set_distributed_count_options(options))
        assert_local_count("/api/hello", 99, **extract_assert_local_count_options(options))

        assert_equal(1, DistributedRateLimitCounter.count)
        counter.reload
        assert_equal(-9223372036854775807 + (sequence_start_val + 6 - 9223372036854775807 - 1), counter.version)
        assert_equal(99, counter.value)
      ensure
        # Restore default sequence settings.
        DistributedRateLimitCounter.connection.execute("ALTER SEQUENCE distributed_rate_limit_counters_version_seq RESTART WITH -9223372036854775807")
      end
    end
  end

  private

  def extract_assert_response_headers_options(options)
    options.slice(:limit_to)
  end

  def assert_response_headers(count, responses, limit_to:)
    reported_requests_made = 0
    responses.each do |response|
      assert_response_code(200, response)
      assert_equal(limit_to.to_s, response.headers["x-ratelimit-limit"])
      assert(response.headers["x-ratelimit-remaining"])
      reported_count = response.headers["x-ratelimit-limit"].to_i - response.headers["x-ratelimit-remaining"].to_i
      if(reported_count > reported_requests_made)
        reported_requests_made = reported_count
      end
    end

    assert_operator(reported_requests_made, :>=, count - 1)
    assert_operator(reported_requests_made, :<=, count)
  end

  def extract_set_distributed_count_options(options)
    options.slice(:api_user, :duration, :time, :host)
  end

  def set_distributed_count(count, api_user:, duration:, time: nil, host: nil)
    time ||= Time.now.utc
    duration_sec = duration / 1000.0
    period_start_time = ((time.to_f / duration_sec).floor * duration_sec).floor
    host ||= "127.0.0.1"
    key = "k|#{format("%g", duration_sec)}|#{host}|#{api_user.api_key_prefix}|#{period_start_time}"
    expires_at = Time.at((period_start_time + (duration_sec * 2) + 60).ceil).utc

    DistributedRateLimitCounter.connection.execute("INSERT INTO distributed_rate_limit_counters(id, value, expires_at) VALUES(#{DistributedRateLimitCounter.connection.quote(key)}, #{DistributedRateLimitCounter.connection.quote(count)}, #{DistributedRateLimitCounter.connection.quote(expires_at)}) ON CONFLICT (id) DO UPDATE SET value = EXCLUDED.value")
  end

  def extract_assert_distributed_count_options(options)
    options.slice(:api_user)
  end

  def assert_distributed_count(expected_count, api_user:)
    # Wait until the distributed count is synced and matches the expected
    # value. Normally this should happen very quickly, but allow some amount
    # of buffer.
    result = nil
    count = nil
    Timeout.timeout(5) do
      loop do
        result = DistributedRateLimitCounter.where("id LIKE '%|' || ? || '|%' AND expires_at >= now()", api_user.api_key_prefix).select("SUM(value) AS total_value").take

        count = 0
        if(result && result["total_value"])
          count = result["total_value"]
        end

        if(count == expected_count)
          assert_equal(expected_count, count)
          break
        end

        sleep 0.1
      end
    end
  rescue Timeout::Error
    flunk("Distributed count does not match expected value after timeout. Expected: #{expected_count.inspect} Last count: #{count.inspect} Last result: #{result.attributes.inspect if(result)}")
  end

  def assert_distributed_count_record(api_user:)
    record = DistributedRateLimitCounter.where("id LIKE '%|' || ? || '|%' AND expires_at >= now()", api_user.api_key_prefix).order("version DESC").first
    assert_equal([
      "id",
      "version",
      "value",
      "expires_at",
    ].sort, record.attributes.keys.sort)
    assert_kind_of(String, record["id"])
    assert_kind_of(Numeric, record["value"])
    assert_kind_of(Time, record["expires_at"])
  end

  def extract_assert_local_count_options(options)
    options.slice(:limit_to, :api_user, :time)
  end

  def assert_local_count(path, expected_count, limit_to:, api_user:, time:)
    # Wait until the local count is synced and matches the expected value.
    # Normally this should happen very quickly, but allow some amount of
    # buffer.
    response = nil
    count = nil
    Timeout.timeout(5) do
      loop do
        http_options = {
          headers: {
            # Use this header as a way to fetch the rate limits from the
            # proxy (returned in the headers) without actually incrementing
            # the number of requests made. This option is only available
            # when running in the test environment.
            "X-Api-Umbrella-Test-Skip-Increment-Limits" => "true",
          },
        }
        response = make_requests(path, 1, api_key: api_user.api_key, time:, http_options:).first
        assert_response_code(200, response)
        assert_equal(limit_to, response.headers["x-ratelimit-limit"].to_i)

        count = limit_to - response.headers["x-ratelimit-remaining"].to_i
        if(count == expected_count)
          assert_equal(expected_count, count)
          break
        end

        sleep 0.1
      end
    end
  rescue Timeout::Error
    flunk("Local count does not match expected value after timeout. Expected: #{expected_count.inspect} Last count: #{count.inspect} Last response: #{response.headers}")
  end

  def extract_make_requests_options(options)
    super(options.merge(api_key: options.fetch(:api_user).api_key))
  end
end

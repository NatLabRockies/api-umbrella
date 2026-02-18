module ApiUmbrellaTestHelpers
  module RateLimits
    private

    def assert_api_key_rate_limit(path, limit, **options)
      assert_allows_up_to_limit_and_then_rejects(path, limit, **options)
      assert_counts_api_keys_separately(path, limit, **options)
      assert_rate_limit_headers(path, limit, **options)
    end

    def assert_ip_rate_limit(path, limit, **options)
      assert_allows_up_to_limit_and_then_rejects(path, limit, **options)
      assert_counts_ips_separately(path, limit, **options)
      assert_rate_limit_headers(path, limit, **options)
    end

    def assert_unlimited_rate_limit(path, limit, **options)
      options[:no_response_headers] = true
      assert_can_exceed_limit(path, limit, **options)
      assert_rate_limit_headers(path, limit, **options)
    end

    def assert_allows_up_to_limit_and_then_rejects(path, limit, **options)
      options[:api_key] ||= create_api_key(**extract_create_api_key_options(options))
      options[:ip] ||= next_unique_ip_addr
      assert_under_rate_limit(path, limit, **options)
      assert_over_rate_limit(path, 1, **options)
    end

    def assert_can_exceed_limit(path, limit, **options)
      options[:api_key] ||= create_api_key(**extract_create_api_key_options(options))
      options[:ip] ||= next_unique_ip_addr
      assert_under_rate_limit(path, limit, **options)
      assert_under_rate_limit(path, 1, **options)
    end

    def assert_counts_api_keys_separately(path, limit, **options)
      options[:api_key] ||= create_api_key(**extract_create_api_key_options(options))
      options[:ip] ||= next_unique_ip_addr
      assert_under_rate_limit(path, limit, **options)
      assert_over_rate_limit(path, 1, **options, ip: next_unique_ip_addr)
      assert_under_rate_limit(path, 1, **options, api_key: create_api_key(**extract_create_api_key_options(options)))
    end

    def assert_counts_ips_separately(path, limit, **options)
      options[:api_key] ||= create_api_key(**extract_create_api_key_options(options))
      options[:ip] ||= next_unique_ip_addr
      assert_under_rate_limit(path, limit, **options)
      assert_over_rate_limit(path, 1, **options, api_key: create_api_key(**extract_create_api_key_options(options)))
      assert_under_rate_limit(path, 1, **options, ip: next_unique_ip_addr)
    end

    def assert_rate_limit_headers(path, limit, no_response_headers: false, **options)
      options[:api_key] ||= create_api_key(**extract_create_api_key_options(options))
      options[:ip] ||= next_unique_ip_addr
      response = make_requests(path, 1, **extract_make_requests_options(options)).first

      if no_response_headers
        refute(response.headers["x-ratelimit-limit"])
        refute(response.headers["x-ratelimit-remaining"])
        refute(response.headers["retry-after"])
      else
        expected_limit = limit
        if(options[:response_header_limit])
          expected_limit = options[:response_header_limit]
        end

        assert_equal(expected_limit.to_s, response.headers["x-ratelimit-limit"])
        assert_equal((expected_limit - 1).to_s, response.headers["x-ratelimit-remaining"])

        if response.headers["x-ratelimit-remaining"] == "0"
          assert(response.headers["retry-after"])
        else
          refute(response.headers["retry-after"])
        end
      end
    end

    def assert_under_rate_limit(path, count, **options)
      responses = make_requests(path, count, **extract_make_requests_options(options))
      responses.each do |response|
        assert_response_code(200, response)
        assert_equal("Hello World", response.body)
      end
    end

    def assert_over_rate_limit(path, count, **options)
      responses = make_requests(path, count, **extract_make_requests_options(options))
      responses.each do |response|
        assert_response_code(429, response)
        assert_match("OVER_RATE_LIMIT", response.body)
      end
    end

    def extract_create_api_key_options(options)
      options.slice(:omit_api_key, :user_factory_overrides)
    end

    def create_api_key(omit_api_key: false, user_factory_overrides: {})
      api_key = nil
      unless omit_api_key
        api_key = FactoryBot.create(:api_user, user_factory_overrides).api_key
      end

      api_key
    end

    def extract_make_requests_options(options)
      options.slice(:max_concurrency, :api_key, :ip, :time, :http_options)
    end

    def make_requests(path, count, max_concurrency: nil, api_key: nil, ip: nil, time: nil, http_options: nil)
      hydra_options = {}
      if max_concurrency
        hydra_options[:max_concurrency] = max_concurrency
      end

      http_opts = keyless_http_options.deep_merge({
        :headers => {},
      })
      if api_key
        http_opts[:headers]["X-Api-Key"] = api_key
      end
      if ip
        http_opts[:headers]["X-Forwarded-For"] = ip
      end

      # When testing rate limits, unless specifically disabled (by passing in
      # `false`), freeze the time used during each test to prevent race
      # conditions in the testing environment and ensure better consistency.
      if time.nil?
        time = rate_limit_frozen_time
      end
      if time
        http_opts[:headers]["X-Fake-Time"] = time.strftime("%s.%L")
      end

      if http_options
        http_opts.deep_merge!(http_options)
      end

      hydra = Typhoeus::Hydra.new(hydra_options)
      requests = Array.new(count) do
        request = Typhoeus::Request.new("http://127.0.0.1:9080#{path}", http_opts)
        hydra.queue(request)
        request
      end
      hydra.run

      assert_equal(count, requests.length)
      requests.map { |r| r.response }
    end

    # Provide a frozen time that is static across all requests within a
    # specific test. This is used for a couple reasons:
    #
    # - The rate limiting algorithm is estimated for performance reasons, so
    #   there can be situations where the user is allowed to exceed the true
    #   rate limit by a couple requests briefly. While this shouldn't be super
    #   common, it can crop up randomly in tests. This can happen due to the
    #   time "buckets" that are used internally, so if the requests happen to
    #   span multiple buckets inside a single test scenario, it could cause the
    #   technical limit to be exceeded briefly.
    # - When testing distributed limits, then similarly, `make_requests` could
    #   populate a different time bucket than `set_distributed_count` sets, so
    #   it's important that we use a static time so both methods can ensure
    #   they're updating the same bucket (even if technically the requests may
    #   span a minute boundary).
    def rate_limit_frozen_time
      @rate_limit_frozen_time ||= Time.now.utc
    end
  end
end

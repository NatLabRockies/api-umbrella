require_relative "../test_helper"

class Test::Proxy::TestTimeoutsRequest < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::RequestBodyStreaming

  # While these tests can be parallelized, given the timing sensitivities of
  # them, we will not parallelize them to cut down on flaky tests due to the
  # timings being skewed by other activity.
  # parallelize_me!

  BUFFER_TIME_LOWER = 0.15
  BUFFER_TIME_UPPER = 1.5

  def setup
    super
    setup_server
    once_per_class_setup do
      override_config_set({
        "nginx" => {
          "proxy_connect_timeout" => 2,
          "proxy_read_timeout" => 10,
          "proxy_send_timeout" => 5,
        },
      })
    end
  end

  def test_request_begins_within_send_timeout
    delay1 = $config["nginx"]["proxy_send_timeout"] - 2
    delay2 = $config["nginx"]["proxy_send_timeout"] + 2
    assert_operator(delay1, :>, 0)
    assert_operator(delay2, :>, 0)
    assert_operator(delay2 - delay1, :>, 0)
    assert_operator(delay2 - delay1, :<, $config["nginx"]["proxy_send_timeout"])

    easy = make_streaming_body_request([
      {
        :data => "foo",
        :sleep => 0,
      },
      {
        :data => "bar",
        :sleep => delay1,
      },
      {
        :data => "baz",
        :sleep => delay2 - delay1,
      },
    ])

    assert_equal(200, easy.response_code)
    data = MultiJson.load(easy.response_body)
    assert_equal(["foo", "bar", "baz"], data.fetch("chunks"))
    assert_equal(3, data.fetch("chunk_time_gaps").length)
    assert_in_delta(0, data.fetch("chunk_time_gaps")[0], 0.3)
    assert_in_delta(delay1, data.fetch("chunk_time_gaps")[1], 0.3)
    assert_in_delta(delay2 - delay1, data.fetch("chunk_time_gaps")[2], 0.3)
    assert_operator(easy.total_time, :>=, delay2 - BUFFER_TIME_LOWER)
    assert_operator(easy.total_time, :<=, delay2 + BUFFER_TIME_UPPER)
  end

  def test_request_sends_chunks_at_least_once_per_send_timeout_interval
    delay1 = 1
    delay2 = $config["nginx"]["proxy_send_timeout"]
    assert_operator(delay1, :>, 0)
    assert_operator(delay2, :>, 0)
    assert_operator(delay2 - delay1, :>, 0)
    assert_operator(delay2 - delay1, :<, $config["nginx"]["proxy_send_timeout"])

    easy = make_streaming_body_request([
      {
        :data => "foo",
        :sleep => 0,
      },
      {
        :data => "bar",
        :sleep => delay1,
      },
      {
        :data => "baz",
        :sleep => delay2 - delay1,
      },
    ])

    assert_equal(200, easy.response_code)
    data = MultiJson.load(easy.response_body)
    assert_equal(["foo", "bar", "baz"], data.fetch("chunks"))
    assert_equal(3, data.fetch("chunk_time_gaps").length)
    assert_in_delta(0, data.fetch("chunk_time_gaps")[0], 0.3)
    assert_in_delta(delay1, data.fetch("chunk_time_gaps")[1], 0.3)
    assert_in_delta(delay2 - delay1, data.fetch("chunk_time_gaps")[2], 0.3)
    assert_operator(easy.total_time, :>=, delay2 - BUFFER_TIME_LOWER)
    assert_operator(easy.total_time, :<=, delay2 + BUFFER_TIME_UPPER)
  end

  def test_request_closes_when_chunk_delay_exceeds_send_timeout
    router_log_tail = LogTail.new("nginx/access.log")
    trafficserver_log_tail = LogTail.new("trafficserver/access.log")
    envoy_log_tail = LogTail.new("envoy/access.log")
    api_backend_log_tail = LogTail.new("test-env-nginx/access.log")

    delay1 = 1
    delay2 = $config["nginx"]["proxy_send_timeout"] + 2
    assert_operator(delay1, :>, 0)
    assert_operator(delay2, :>, 0)
    assert_operator(delay2 - delay1, :>, 0)
    assert_operator(delay2 - delay1, :>, $config["nginx"]["proxy_send_timeout"])

    easy = make_streaming_body_request([
      {
        :data => "foo",
        :sleep => 0,
      },
      {
        :data => "bar",
        :sleep => delay1,
      },
      {
        :data => "baz",
        :sleep => delay2 - delay1,
      },
    ], url: "http://127.0.0.1:9080/api/request-body-streaming/?unique_test_id=#{unique_test_id}")

    assert_equal(408, easy.response_code)
    assert_match("Inactivity Timeout", easy.response_body)
    expected_timeout = delay1 + $config["nginx"]["proxy_send_timeout"]
    assert_operator(easy.total_time, :>=, expected_timeout - BUFFER_TIME_LOWER)
    assert_operator(easy.total_time, :<=, expected_timeout + BUFFER_TIME_UPPER)

    # Verify the request that timed out was aborted in all of the different
    # server layers after the expected timeout time (to ensure the request
    # didn't just timeout at one layer, but is still running at other layers).
    router_log = MultiJson.load(router_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    router_time = router_log.fetch("duration").to_f
    assert_operator(router_time, :>, expected_timeout - BUFFER_TIME_LOWER)
    assert_operator(router_time, :<=, expected_timeout + BUFFER_TIME_UPPER)
    assert_equal("408", router_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("408", router_log.fetch("up_status"))

    trafficserver_log = MultiJson.load(trafficserver_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    trafficserver_time = trafficserver_log.fetch("duration").to_f / 1000
    assert_operator(trafficserver_time, :>, expected_timeout - BUFFER_TIME_LOWER)
    assert_operator(trafficserver_time, :<=, expected_timeout + BUFFER_TIME_UPPER)
    assert_equal("408", trafficserver_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("000", trafficserver_log.fetch("up_status"))
    assert_equal("FIN", trafficserver_log.fetch("client_finish"))
    assert_equal("FIN", trafficserver_log.fetch("proxy_finish"))
    assert_equal("-", trafficserver_log.fetch("req_err"))
    assert_equal("-", trafficserver_log.fetch("resp_err"))

    envoy_log = MultiJson.load(envoy_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    envoy_time = envoy_log.fetch("duration").to_f / 1000
    assert_operator(envoy_time, :>, expected_timeout - BUFFER_TIME_LOWER)
    assert_operator(envoy_time, :<=, expected_timeout + BUFFER_TIME_UPPER)
    assert_equal(0, envoy_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("DC", envoy_log.fetch("resp_flags"))
    assert_equal("downstream_remote_disconnect", envoy_log.fetch("resp_detail"))
    assert_nil(envoy_log.fetch("up_fail"))

    api_backend_log = MultiJson.load(api_backend_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    api_backend_time = api_backend_log.fetch("duration").to_f
    assert_operator(api_backend_time, :>, expected_timeout - BUFFER_TIME_LOWER)
    assert_operator(api_backend_time, :<=, expected_timeout + BUFFER_TIME_UPPER)
    assert_equal("000", api_backend_log.fetch("http").fetch("response").fetch("status_code"))
  end

  # This is mainly done to ensure that any connection collapsing the cache is
  # doing, doesn't improperly hold up non-cacheable requests waiting on a
  # potentially cacheable request.
  def test_concurrent_requests_to_same_url_different_http_method
    delay = $config["nginx"]["proxy_read_timeout"] - 1
    assert_operator(delay, :>, 0)

    start_time = Time.now.utc

    get_thread = Thread.new do
      Thread.current[:response] = Typhoeus.get("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options)
    end

    # Wait 1 second to ensure the first GET request is fully established to the
    # backend.
    sleep 1

    post_thread = Thread.new do
      Thread.current[:response] = Typhoeus.post("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options)
    end

    get_thread.join
    post_thread.join
    total_time = Time.now.utc - start_time

    assert_response_code(200, get_thread[:response])
    assert_response_code(200, post_thread[:response])

    # Sanity check to ensure the 2 requests were made in parallel and
    # overlapped.
    assert_operator(get_thread[:response].total_time, :>=, delay - BUFFER_TIME_LOWER)
    assert_operator(get_thread[:response].total_time, :<, delay + BUFFER_TIME_UPPER)
    assert_operator(post_thread[:response].total_time, :>=, delay - BUFFER_TIME_LOWER)
    assert_operator(post_thread[:response].total_time, :<, delay + BUFFER_TIME_UPPER)
    assert_operator(total_time, :>=, delay + 1 - BUFFER_TIME_LOWER)
    assert_operator(total_time, :<, delay + (BUFFER_TIME_UPPER * 2))
    assert_operator(total_time, :<, (delay * 2) - 1)
  end

  # This is to ensure that no proxy in front of the backend makes multiple
  # retry attempts when a request times out (since we don't want to duplicate
  # requests if a backend is already struggling).
  def test_no_request_retry_get
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=get-timeout")
    assert_response_code(200, response)
    assert_equal("0", response.body)

    response = Typhoeus.get("http://127.0.0.1:9080/api/delay-sec/20?backend_counter_id=get-timeout", http_options)
    assert_response_code(504, response)
    assert_match("Inactivity Timeout", response.body)

    # Ensure that the backend has only been called once.
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=get-timeout")
    assert_response_code(200, response)
    assert_equal("1", response.body)

    # Wait 5 seconds for any possible retry attempts that might be pending, and
    # then ensure the backend has still only been called once.
    sleep 5
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=get-timeout")
    assert_response_code(200, response)
    assert_equal("1", response.body)
  end

  # Same test as above, but ensure non-GET requests are behaving the same (no
  # retry allowed). This is probably even more important for non-GET requests
  # since duplicating POST requests could be harmful (multiple creates,
  # updates, etc).
  def test_no_request_retry_post
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=#{unique_test_id}")
    assert_response_code(200, response)
    assert_equal("0", response.body)

    response = Typhoeus.post("http://127.0.0.1:9080/api/delay-sec/20?backend_counter_id=#{unique_test_id}", http_options)
    assert_response_code(504, response)
    assert_match("Inactivity Timeout", response.body)

    # Ensure that the backend has only been called once.
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=#{unique_test_id}")
    assert_response_code(200, response)
    assert_equal("1", response.body)

    # Wait 5 seconds for any possible retry attempts that might be pending, and
    # then ensure the backend has still only been called once.
    sleep 5
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=#{unique_test_id}")
    assert_response_code(200, response)
    assert_equal("1", response.body)
  end

  # Since we have slightly different timeouts at the different layers (nginx vs
  # Trafficserver), ensure there's no retries or other odd behavior when the
  # response times are right around the timeout length.
  def test_no_request_retry_when_timeout_between_layer_timeouts
    start_delay = $config["nginx"]["proxy_connect_timeout"] - 1
    end_delay = $config["nginx"]["proxy_read_timeout"] * 2
    assert_operator(start_delay, :>, 0)
    assert_operator(start_delay, :<, end_delay)

    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=#{unique_test_id}")
    assert_response_code(200, response)
    assert_equal("0", response.body)

    hydra = Typhoeus::Hydra.new
    requests = []
    delay = start_delay
    while delay <= end_delay
      request = Typhoeus::Request.new("http://127.0.0.1:9080/api/delay-sec/#{delay}?backend_counter_id=#{unique_test_id}", http_options)
      hydra.queue(request)

      requests << {
        :request => request,
        :delay => delay,
      }

      delay += 0.5
    end
    hydra.run

    timeout_count = 0
    ok_count = 0
    either_count = 0
    requests.each do |req|
      if req.fetch(:delay) > $config["nginx"]["proxy_read_timeout"] + 1
        timeout_count += 1
        assert_response_code(504, req.fetch(:request).response)
        assert_match("Inactivity Timeout", req.fetch(:request).response.body)
      elsif req.fetch(:delay) < $config["nginx"]["proxy_read_timeout"]
        ok_count += 1
        assert_response_code(200, req.fetch(:request).response)
      else
        # For requests in the vicinity of the timeout, either a timeout or an
        # ok response may happen due to various timing edge cases.
        either_count += 1
      end
    end

    assert_operator(timeout_count, :>=, 6)
    assert_operator(ok_count, :>=, 6)
    assert_operator(either_count, :>=, 3)
    assert_operator(either_count, :<=, 6)

    # Ensure that the backend has only been called once for each test.
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=#{unique_test_id}")
    assert_response_code(200, response)
    assert_equal(requests.length.to_s, response.body)

    # Wait 5 seconds for any possible retry attempts that might be pending, and
    # then ensure the backend has still only been called once.
    sleep 5
    response = Typhoeus.get("http://127.0.0.1:9442/backend_call_count?id=#{unique_test_id}")
    assert_response_code(200, response)
    assert_equal(requests.length.to_s, response.body)
  end
end

require_relative "../test_helper"

class Test::Proxy::TestTimeoutsResponse < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

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
          "proxy_read_timeout" => 5,
          "proxy_send_timeout" => 10,
        },
      })
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_response_sent_before_timeout
    read_timeout = $config["nginx"]["proxy_read_timeout"]
    delay = read_timeout - 2
    assert_operator(delay, :>, 0)
    assert_operator(delay, :<, read_timeout)

    response = Typhoeus.get("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options)
    assert_response_code(200, response)
    assert_operator(response.total_time, :>, delay - BUFFER_TIME_LOWER)
  end

  def test_response_sent_after_timeout
    router_log_tail = LogTail.new("nginx/access.log")
    trafficserver_log_tail = LogTail.new("trafficserver/access.log")
    envoy_log_tail = LogTail.new("envoy/access.log")
    api_backend_log_tail = LogTail.new("test-env-nginx/access.log")

    read_timeout = $config["nginx"]["proxy_read_timeout"]
    delay = read_timeout + 2
    assert_operator(delay, :>, read_timeout)
    assert_operator(delay, :>, read_timeout + BUFFER_TIME_UPPER)
    assert_operator(delay, :<, read_timeout + (BUFFER_TIME_UPPER * 2))

    response = Typhoeus.get("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options.deep_merge({
      params: {
        unique_test_id: unique_test_id,
      },
    }))
    assert_response_code(504, response)
    assert_match("Inactivity Timeout", response.body)
    client_time = response.total_time
    assert_operator(client_time, :>, read_timeout - BUFFER_TIME_LOWER)
    assert_operator(client_time, :<=, read_timeout + BUFFER_TIME_UPPER)

    # Verify the request that timed out was aborted in all of the different
    # server layers after the expected timeout time (to ensure the request
    # didn't just timeout at one layer, but is still running at other layers).
    router_log = MultiJson.load(router_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    router_time = router_log.fetch("duration").to_f
    assert_operator(router_time, :>, read_timeout - BUFFER_TIME_LOWER)
    assert_operator(router_time, :<=, read_timeout + BUFFER_TIME_UPPER)
    assert_equal("504", router_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("504", router_log.fetch("up_status"))

    trafficserver_log = MultiJson.load(trafficserver_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    trafficserver_time = trafficserver_log.fetch("duration").to_f / 1000
    assert_operator(trafficserver_time, :>, read_timeout - BUFFER_TIME_LOWER)
    assert_operator(trafficserver_time, :<=, read_timeout + BUFFER_TIME_UPPER)
    assert_equal("504", trafficserver_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("000", trafficserver_log.fetch("up_status"))
    assert_equal("FIN", trafficserver_log.fetch("client_finish"))
    assert_equal("TIMEOUT", trafficserver_log.fetch("proxy_finish"))
    assert_equal("-", trafficserver_log.fetch("req_err"))
    assert_equal("-", trafficserver_log.fetch("resp_err"))

    envoy_log = MultiJson.load(envoy_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    envoy_time = envoy_log.fetch("duration").to_f / 1000
    assert_operator(envoy_time, :>, read_timeout - BUFFER_TIME_LOWER)
    assert_operator(envoy_time, :<=, read_timeout + BUFFER_TIME_UPPER)
    assert_equal(0, envoy_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("DC", envoy_log.fetch("resp_flags"))
    assert_equal("downstream_remote_disconnect", envoy_log.fetch("resp_detail"))
    assert_nil(envoy_log.fetch("up_fail"))

    api_backend_log = MultiJson.load(api_backend_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    api_backend_time = api_backend_log.fetch("duration").to_f
    assert_operator(api_backend_time, :>, read_timeout - BUFFER_TIME_LOWER)
    assert_operator(api_backend_time, :<=, read_timeout + BUFFER_TIME_UPPER)
    assert_equal("499", api_backend_log.fetch("http").fetch("response").fetch("status_code"))
  end

  def test_response_begins_within_read_timeout
    delay1 = $config["nginx"]["proxy_read_timeout"] - 2
    delay2 = $config["nginx"]["proxy_read_timeout"] + 2
    assert_operator(delay1, :>, 0)
    assert_operator(delay2, :>, 0)
    assert_operator(delay2 - delay1, :>, 0)
    assert_operator(delay2 - delay1, :<, $config["nginx"]["proxy_read_timeout"])

    response = Typhoeus.post("http://127.0.0.1:9080/api/delays-sec/#{delay1}/#{delay2}", http_options)
    assert_response_code(200, response)
    assert_equal("firstdone", response.body)
    assert_operator(response.total_time, :>=, delay2 - BUFFER_TIME_LOWER)
    assert_operator(response.total_time, :<=, delay2 + BUFFER_TIME_UPPER)
  end

  def test_response_sends_chunks_at_least_once_per_read_timeout_interval
    delay1 = 1
    delay2 = $config["nginx"]["proxy_read_timeout"]
    assert_operator(delay1, :>, 0)
    assert_operator(delay2, :>, 0)
    assert_operator(delay2 - delay1, :>, 0)
    assert_operator(delay2 - delay1, :<, $config["nginx"]["proxy_read_timeout"])

    response = Typhoeus.post("http://127.0.0.1:9080/api/delays-sec/#{delay1}/#{delay2}", http_options)
    assert_response_code(200, response)
    assert_equal("firstdone", response.body)
    assert_operator(response.total_time, :>=, delay2 - BUFFER_TIME_LOWER)
    assert_operator(response.total_time, :<=, delay2 + BUFFER_TIME_UPPER)
  end

  def test_response_closes_when_chunk_delay_exceeds_read_timeout
    delay1 = 1
    delay2 = $config["nginx"]["proxy_read_timeout"] + 2
    assert_operator(delay1, :>, 0)
    assert_operator(delay2, :>, 0)
    assert_operator(delay2 - delay1, :>, 0)
    assert_operator(delay2 - delay1, :>, $config["nginx"]["proxy_read_timeout"])

    response = Typhoeus.post("http://127.0.0.1:9080/api/delays-sec/#{delay1}/#{delay2}", http_options)
    assert_response_code(200, response)
    assert_equal("first", response.body)
    assert_operator(response.total_time, :>=, delay1 + $config["nginx"]["proxy_read_timeout"] - BUFFER_TIME_LOWER)
    assert_operator(response.total_time, :<=, delay1 + $config["nginx"]["proxy_read_timeout"] + BUFFER_TIME_UPPER)
  end

  # This is to check the behavior of Trafficserver's
  # "proxy.config.http.down_server.cache_time" configuration, to ensure a bunch
  # of backend timeouts don't remove all the servers from rotation.
  def test_backend_remains_in_rotation_after_timeouts
    timeout_hydra = Typhoeus::Hydra.new
    timeout_requests = Array.new(50) do
      delay = $config["nginx"]["proxy_read_timeout"] + 2
      request = Typhoeus::Request.new("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options)
      timeout_hydra.queue(request)
      request
    end
    timeout_hydra.run

    info_hydra = Typhoeus::Hydra.new
    info_requests = Array.new(50) do
      request = Typhoeus::Request.new("http://127.0.0.1:9080/api/info/", http_options)
      info_hydra.queue(request)
      request
    end
    info_hydra.run

    assert_equal(50, timeout_requests.length)
    timeout_requests.each do |request|
      assert_response_code(504, request.response)
      assert_match("Inactivity Timeout", request.response.body)
    end

    assert_equal(50, info_requests.length)
    info_requests.each do |request|
      assert_response_code(200, request.response)
    end
  end

  def test_client_aborted_requests_before_response_propagate_to_all_layers
    router_log_tail = LogTail.new("nginx/access.log")
    trafficserver_log_tail = LogTail.new("trafficserver/access.log")
    envoy_log_tail = LogTail.new("envoy/access.log")
    api_backend_log_tail = LogTail.new("test-env-nginx/access.log")

    read_timeout = $config["nginx"]["proxy_read_timeout"]
    delay = read_timeout + 10
    assert_operator(delay, :>, read_timeout + BUFFER_TIME_UPPER)

    client_timeout = 2
    assert_operator(client_timeout, :<, read_timeout - BUFFER_TIME_LOWER - BUFFER_TIME_UPPER)

    response = Typhoeus.get("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options.deep_merge({
      timeout: client_timeout,
      params: {
        unique_test_id: unique_test_id,
      },
    }))
    assert_response_code(0, response)
    assert_equal(:operation_timedout, response.return_code)
    assert_equal("", response.body)
    client_time = response.total_time
    assert_operator(client_time, :>, client_timeout - BUFFER_TIME_LOWER)
    assert_operator(client_time, :<=, client_timeout + BUFFER_TIME_UPPER)

    router_log = MultiJson.load(router_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    router_time = router_log.fetch("duration").to_f
    assert_operator(router_time, :>, client_timeout - BUFFER_TIME_LOWER)
    assert_operator(router_time, :<=, client_timeout + BUFFER_TIME_UPPER)
    assert_equal("499", router_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("-", router_log.fetch("up_status"))

    trafficserver_log = MultiJson.load(trafficserver_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    trafficserver_time = trafficserver_log.fetch("duration").to_f / 1000
    assert_operator(trafficserver_time, :>, client_timeout - BUFFER_TIME_LOWER)
    assert_operator(trafficserver_time, :<=, client_timeout + BUFFER_TIME_UPPER)
    assert_equal("000", trafficserver_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("000", trafficserver_log.fetch("up_status"))
    assert_equal("INTR", trafficserver_log.fetch("client_finish"))
    assert_equal("FIN", trafficserver_log.fetch("proxy_finish"))
    assert_equal("-", trafficserver_log.fetch("req_err"))
    assert_equal("-", trafficserver_log.fetch("resp_err"))

    envoy_log = MultiJson.load(envoy_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    envoy_time = envoy_log.fetch("duration").to_f / 1000
    assert_operator(envoy_time, :>, client_timeout - BUFFER_TIME_LOWER)
    assert_operator(envoy_time, :<=, client_timeout + BUFFER_TIME_UPPER)
    assert_equal(0, envoy_log.fetch("http").fetch("response").fetch("status_code"))
    assert_equal("DC", envoy_log.fetch("resp_flags"))
    assert_equal("downstream_remote_disconnect", envoy_log.fetch("resp_detail"))
    assert_nil(envoy_log.fetch("up_fail"))

    api_backend_log = MultiJson.load(api_backend_log_tail.read_until(unique_test_id, timeout: 30).match(/^.*#{unique_test_id}.*$/)[0])
    api_backend_time = api_backend_log.fetch("duration").to_f
    assert_operator(api_backend_time, :>, client_timeout - BUFFER_TIME_LOWER)
    assert_operator(api_backend_time, :<=, client_timeout + BUFFER_TIME_UPPER)
    assert_equal("499", api_backend_log.fetch("http").fetch("response").fetch("status_code"))
  end
end

require_relative "../../test_helper"

class Test::Proxy::KeepAlive::TestServerSide < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server

    once_per_class_setup do
      prepend_api_backends([
        {
          :name => unique_test_class_id,
          :frontend_host => "127.0.0.1",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/keepalive-default/", :backend_prefix => "/" }],
        },
      ])
      @@api_backend = ApiBackend.find_by!(name: unique_test_class_id)
    end

    reset_api_backend_idle_connections
  end

  def test_keeps_idle_connections_open
    nginx_workers = 2
    nginx_upstream_keepalive_connections_per_worker = 15
    nginx_upstream_keepalive_idle_timeout = 3
    trafficserver_upstream_keepalive_idle_timeout = 6
    envoy_upstream_keepalive_idle_timeout = 9
    override_config({
      :nginx => {
        :workers => nginx_workers,
        :upstream_keepalive_connections_per_worker => nginx_upstream_keepalive_connections_per_worker,
        :upstream_keepalive_idle_timeout => nginx_upstream_keepalive_idle_timeout,
      },
      :trafficserver => {
        :records => {
          :http => {
            :keep_alive_no_activity_timeout_out => trafficserver_upstream_keepalive_idle_timeout,
          },
        },
      },
      :router => {
        :api_backends => {
          :keepalive_idle_timeout => envoy_upstream_keepalive_idle_timeout,
        },
      },
    }) do
      assert_idle_connections("/#{unique_test_class_id}/keepalive-default/delay/500",
        nginx_workers: nginx_workers,
        nginx_upstream_keepalive_connections_per_worker: nginx_upstream_keepalive_connections_per_worker,
        nginx_upstream_keepalive_idle_timeout: nginx_upstream_keepalive_idle_timeout,
        trafficserver_upstream_keepalive_idle_timeout: trafficserver_upstream_keepalive_idle_timeout,
        envoy_upstream_keepalive_idle_timeout: envoy_upstream_keepalive_idle_timeout)
    end
  end

  # Same test as above, but with the layers having opposite timeout order than
  # normal just to verify that further back layers closing connections first
  # doesn't cause issues for subsequent requests.
  def test_keeps_idle_connections_open_verify_layers
    nginx_workers = 2
    nginx_upstream_keepalive_connections_per_worker = 15
    nginx_upstream_keepalive_idle_timeout = 9
    trafficserver_upstream_keepalive_idle_timeout = 6
    envoy_upstream_keepalive_idle_timeout = 3
    override_config({
      :nginx => {
        :workers => nginx_workers,
        :upstream_keepalive_connections_per_worker => nginx_upstream_keepalive_connections_per_worker,
        :upstream_keepalive_idle_timeout => nginx_upstream_keepalive_idle_timeout,
      },
      :trafficserver => {
        :records => {
          :http => {
            :keep_alive_no_activity_timeout_out => trafficserver_upstream_keepalive_idle_timeout,
          },
        },
      },
      :router => {
        :api_backends => {
          :keepalive_idle_timeout => envoy_upstream_keepalive_idle_timeout,
        },
      },
    }) do
      assert_idle_connections("/#{unique_test_class_id}/keepalive-default/delay/500",
        nginx_workers: nginx_workers,
        nginx_upstream_keepalive_connections_per_worker: nginx_upstream_keepalive_connections_per_worker,
        nginx_upstream_keepalive_idle_timeout: nginx_upstream_keepalive_idle_timeout,
        trafficserver_upstream_keepalive_idle_timeout: trafficserver_upstream_keepalive_idle_timeout,
        envoy_upstream_keepalive_idle_timeout: envoy_upstream_keepalive_idle_timeout)
    end
  end

  def test_max_connection_age_closes_connections
    envoy_upstream_keepalive_connections_max_age = 5
    envoy_upstream_keepalive_idle_timeout = 120
    override_config({
      :router => {
        :api_backends => {
          # Set a long idle timeout so it doesn't interfere with the max age
          # behavior being tested.
          :keepalive_idle_timeout => envoy_upstream_keepalive_idle_timeout,
          :keepalive_connections_max_age => envoy_upstream_keepalive_connections_max_age,
        },
      },
    }) do
      # Open a bunch of concurrent connections to establish a connection pool.
      max_concurrency = 100
      saturate_connections("/#{unique_test_class_id}/keepalive-default/delay/500", num_requests: 300, max_concurrency: max_concurrency)

      # Immediately after the requests, verify that Envoy has idle connections
      # to the API backend (the connection pool is populated).
      stats = connection_stats
      max_concurrency_delta_buffer = (max_concurrency * 0.3).round
      assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy), max_concurrency_delta_buffer)
      assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend), max_concurrency_delta_buffer)
      assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend), max_concurrency_delta_buffer)

      # Record the baseline count of locally-destroyed connections.
      baseline_destroy_local = stats.fetch(:envoy_to_api_backend_destroy_local_connections_per_envoy)

      # Wait for the max connection age to expire and verify Envoy closes the
      # connections, even though the idle timeout (120s) hasn't been reached.
      # Also measure the timing to verify it corresponds with the configured
      # max age setting.
      begin_time = Time.now
      timing = nil
      begin
        stats = nil
        # This should generally happen within the configured timeout seconds.
        Timeout.timeout(envoy_upstream_keepalive_connections_max_age * 3) do
          loop do
            stats = connection_stats
            elapsed_time = Time.now - begin_time

            # Once Envoy's active connections to the API backend drop to zero,
            # note the elapsed time.
            if !timing && stats.fetch(:envoy_to_api_backend_active_connections_per_envoy) == 0
              timing = elapsed_time
              break
            end

            sleep 0.1
          end
        end
      rescue Timeout::Error
        flunk("Envoy did not close connections after max connection age expired. Last connection stats: #{stats.inspect}")
      end

      # Verify Envoy closed the connections and the API backend agrees
      # (although, note that nginx may still think there are some connections
      # remaining open, but we're not trying to test that backend behavior
      # here, so accept some discrepancies there).
      stats = connection_stats
      assert_equal(0, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy))
      assert_operator(stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend), :<=, max_concurrency_delta_buffer)
      assert_operator(stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend), :<=, max_concurrency_delta_buffer)

      # Verify that Envoy initiated the connection closures (destroy_local
      # should have increased to correspond to the number of max connections
      # established).
      num_destroyed = stats.fetch(:envoy_to_api_backend_destroy_local_connections_per_envoy) - baseline_destroy_local
      assert_in_delta(max_concurrency, num_destroyed, max_concurrency_delta_buffer)

      # Check the timing of when connections were closed. This verifies that
      # the observed behavior corresponds with the configured max age setting.
      assert_in_delta(envoy_upstream_keepalive_connections_max_age, timing, 2)

      # Make another batch of requests after the max age has expired to ensure
      # that new connections work successfully.
      saturate_connections("/#{unique_test_class_id}/keepalive-default/delay/500", num_requests: 300, max_concurrency: max_concurrency)

      # Verify new connections were established.
      stats = connection_stats
      assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy), max_concurrency_delta_buffer)
      assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend), max_concurrency_delta_buffer)
      assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend), max_concurrency_delta_buffer)
    end
  end

  def test_concurrent_backend_connections_can_exceed_keepalive_count
    max_values = {
      client_to_nginx_router_active_connections_per_nginx_router: 0,
      client_to_nginx_router_writing_connections_per_nginx_router: 0,
      nginx_router_to_trafficserver_active_connections_per_trafficserver: 0,
      trafficserver_to_envoy_active_connections_per_trafficserver: 0,
      trafficserver_to_envoy_active_connections_per_envoy: 0,
      envoy_to_api_backend_active_connections_per_envoy: 0,
      envoy_to_api_backend_active_connections_per_api_backend: 0,
      envoy_to_api_backend_writing_connections_per_api_backend: 0,
    }

    # Make a bunch of parallel requests and periodically check the full stats
    # of each layer.
    hydra = Typhoeus::Hydra.new(max_concurrency: 200)
    requests = Array.new(500) do |i|
      request = Typhoeus::Request.new("http://127.0.0.1:9080/#{unique_test_class_id}/keepalive-default/delay/500", http_options)
      request.on_complete do |response|
        # Fetch the full stats periodically while the concurrent requests are
        # going on.
        if i % 10 == 0
          stats = connection_stats
          max_values.each do |key, value|
            new_value = stats.fetch(key)
            if new_value > value
              max_values[key] = new_value
            end
          end
        end
      end
      hydra.queue(request)
      request
    end
    hydra.run
    assert_equal(500, requests.length)
    requests.each do |req|
      assert_response_code(200, req.response)
    end

    # Ensure that the number of concurrent requests at each layer at some point
    # exceeded the default number of keepalive connections configured at the
    # nginx layer.
    nginx_keepalive_count = $config["nginx"]["upstream_keepalive_connections_per_worker"] * $config["nginx"]["workers"]
    max_values.each do |key, value|
      assert_operator(value, :>, nginx_keepalive_count + 2, "Maximum concurrency observed for #{key.inspect} did not meet expectations")
    end
  end

  private

  def reset_api_backend_idle_connections
    # Restart the various layers to close any persistent keep-alive connections
    # API Umbrella is holding against it.
    api_umbrella_process.restart_services(["envoy", "test-env-nginx", "trafficserver"])

    # After restarting services verify there are no idle connections, so our
    # checks for counts are isolated to each test.
    begin
      stats = nil
      Timeout.timeout(10) do
        loop do
          stats = connection_stats
          if stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend) == 0
            break
          end

          sleep 0.1
        end
      end
    rescue Timeout::Error
      flunk("nginx still has idle connections waiting. This is not expected after the reload. Last connection stats: #{data.inspect}")
    end
  end

  def assert_idle_connections(path, nginx_workers:, nginx_upstream_keepalive_connections_per_worker:, nginx_upstream_keepalive_idle_timeout:, trafficserver_upstream_keepalive_idle_timeout:, envoy_upstream_keepalive_idle_timeout:)
    # After just making one connection, sanity check the keepalive connections
    # to ensure it's just few (for the current connection). Keepalive
    # connections are lazily established, so this just verifies the current
    # behavior of the connections only being kept once they're actually used.
    response = Typhoeus.get("http://127.0.0.1:9080#{path}", http_options)
    assert_response_code(200, response)
    stats = connection_stats
    assert_includes(1..4, stats.fetch(:nginx_router_to_trafficserver_active_connections_per_trafficserver))
    assert_includes(1..4, stats.fetch(:trafficserver_to_envoy_active_connections_per_trafficserver))
    assert_includes(1..4, stats.fetch(:trafficserver_to_envoy_active_connections_per_envoy))
    assert_includes(1..4, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy))
    assert_includes(1..4, stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend))
    assert_includes(1..4, stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend))

    # Open a bunch of concurrent connections first, and then inspect the number
    # of number of connections still active afterwards.
    max_concurrency = 190
    saturate_connections(path, num_requests: 500, max_concurrency: max_concurrency)

    # Immediately after opening all the connections, the server should have a
    # bunch of idle connections open, roughly corresponding to the maximum
    # concurrency we hit. The exception is the initial nginx router to
    # TrafficServer, which only keeps around the configured number of keepalive
    # connections. It's okay if this behavior changes in the future, just
    # wanting to document each layer now.
    stats = connection_stats
    max_concurrency_delta_buffer = (max_concurrency * 0.3).round
    nginx_keepalive_count = nginx_upstream_keepalive_connections_per_worker * nginx_workers
    nginx_keepalive_count_delta_buffer = (nginx_keepalive_count * 0.3).round
    assert_in_delta(nginx_keepalive_count, stats.fetch(:nginx_router_to_trafficserver_active_connections_per_trafficserver), nginx_keepalive_count_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:trafficserver_to_envoy_active_connections_per_trafficserver), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:trafficserver_to_envoy_active_connections_per_envoy), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend), max_concurrency_delta_buffer)

    # Make another batch of concurrent requests just to sanity check that the
    # existing idle connections get reused instead of being reestablished.
    saturate_connections(path, num_requests: 300, max_concurrency: max_concurrency)

    stats = connection_stats
    assert_in_delta(nginx_keepalive_count, stats.fetch(:nginx_router_to_trafficserver_active_connections_per_trafficserver), nginx_keepalive_count_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:trafficserver_to_envoy_active_connections_per_trafficserver), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:trafficserver_to_envoy_active_connections_per_envoy), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend), max_concurrency_delta_buffer)

    # Wait for the keepalive timeouts across all stacks to expire, and measure
    # how long each stack takes to reach their timeout. This way we can measure
    # the keepalive behavior of each layer in our stack so verify the
    # configuration behavior.
    begin_time = Time.now
    timing = {}
    begin
      stats = nil
      # This should generally happen within the configured timeout seconds, but
      # we'll add a significant timeout since we sometimes see this take longer
      # in CI (but the exact timing of this behavior isn't really that
      # important).
      Timeout.timeout(300) do
        loop do
          stats = connection_stats
          elapsed_time = Time.now - begin_time

          # Once the active connections to Traffic Server drop significantly,
          # note the elapsed time. This corresponds to the Nginx to Traffic
          # Server timeout behavior.
          if !timing[:nginx_router_to_trafficserver] && stats.fetch(:nginx_router_to_trafficserver_active_connections_per_trafficserver) <= nginx_keepalive_count_delta_buffer
            timing[:nginx_router_to_trafficserver] = elapsed_time
          end

          # Once the active connections to Envoy drop significantly, note the
          # elapsed time. This corresponds to the Traffic Server to Envoy
          # timeout behavior.
          if !timing[:trafficserver_to_envoy] && stats.fetch(:trafficserver_to_envoy_active_connections_per_envoy) <= max_concurrency_delta_buffer
            timing[:trafficserver_to_envoy] = elapsed_time
          end

          # Once the active connections to the API backend drop significantly,
          # note the elapse time. This corresponds to the Envoy to API backend
          # timeout behavior.
          if !timing[:envoy_to_api_backend] && stats.fetch(:envoy_to_api_backend_active_connections_per_envoy) <= max_concurrency_delta_buffer
            timing[:envoy_to_api_backend] = elapsed_time
          end

          # Once all of the timeouts have been exercised, break out of this
          # loop.
          if stats.fetch(:nginx_router_to_trafficserver_active_connections_per_trafficserver) <= nginx_keepalive_count_delta_buffer && stats.fetch(:trafficserver_to_envoy_active_connections_per_envoy) == 0 && stats.fetch(:envoy_to_api_backend_active_connections_per_envoy) == 0
            break
          end

          sleep 0.1
        end
      end
    rescue Timeout::Error
      flunk("nginx did not reduce the number of idle keepalive connections kept after the expected timeout period. Last connection stats: #{stats.inspect}")
    end

    # After all of the keepalive timeouts expires, check the stats again to
    # ensure we've hit all of the timeouts in the stack as expected.
    stats = connection_stats
    assert_operator(stats.fetch(:nginx_router_to_trafficserver_active_connections_per_trafficserver), :<=, nginx_keepalive_count_delta_buffer)
    assert_operator(stats.fetch(:trafficserver_to_envoy_active_connections_per_trafficserver), :<=, 1)
    assert_equal(0, stats.fetch(:trafficserver_to_envoy_active_connections_per_envoy))
    assert_equal(0, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy))
    # Enovy closes its connections to the API backend (as the above stats
    # indicate), but theoretically nginx thinks there are some remaining open
    # until the API backend's own `http.keepalive_timeout` is hit. But since
    # we're not really trying to test that backend behavior, we just want to
    # verify that the API backend thinks most of the connections are closed.
    assert_operator(stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend), :<=, nginx_keepalive_count_delta_buffer)
    assert_operator(stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend), :<=, nginx_keepalive_count_delta_buffer)

    # Check the timings of when each layer in the stack started to close its
    # connections. This verifies that the observed keepalive behavior
    # corresponds with the configured settings. The 2 second buffer assumes at
    # least a 3 second difference is being used in the test environment for
    # each layer's timing so that we can distinguish each one.
    assert_in_delta(nginx_upstream_keepalive_idle_timeout, timing.fetch(:nginx_router_to_trafficserver), 2)
    assert_in_delta(trafficserver_upstream_keepalive_idle_timeout, timing.fetch(:trafficserver_to_envoy), 2)
    assert_in_delta(envoy_upstream_keepalive_idle_timeout, timing.fetch(:envoy_to_api_backend), 2)

    # Sanity check that the only request being made to the API backend should
    # be the one to fetch connection stats.
    assert_equal(1, stats.fetch(:envoy_to_api_backend_writing_connections_per_api_backend))

    # Make another batch of requests after all of the timeouts have expired
    # just to ensure that new connections work successfully and any stale
    # connections (like the API backend and Envoy having a different concept of
    # what connections are idle) work properly.
    saturate_connections(path, num_requests: 300, max_concurrency: max_concurrency)

    stats = connection_stats
    assert_in_delta(nginx_keepalive_count, stats.fetch(:nginx_router_to_trafficserver_active_connections_per_trafficserver), nginx_keepalive_count_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:trafficserver_to_envoy_active_connections_per_trafficserver), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:trafficserver_to_envoy_active_connections_per_envoy), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_envoy), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_active_connections_per_api_backend), max_concurrency_delta_buffer)
    assert_in_delta(max_concurrency, stats.fetch(:envoy_to_api_backend_idle_connections_per_api_backend), max_concurrency_delta_buffer)
  end

  def connection_stats
    stats = {}

    response = Typhoeus.get("http://127.0.0.1:9080/_nginx_status", http_options)
    assert_response_code(200, response)
    stats[:nginx_router] = MultiJson.load(response.body)

    response = Typhoeus.get("http://127.0.0.1:13001/stats", http_options.deep_merge({
      params: {
        format: "json",
        filter: "(downstream_cx|upstream_cx)",
      },
    }))
    assert_response_code(200, response)
    stats[:envoy] = MultiJson.load(response.body).fetch("stats").each_with_object({}) { |stat, data| data[stat["name"]] = stat["value"] if stat["name"] }

    response = Typhoeus.get("http://127.0.0.1:13009/_trafficserver_stats", http_options)
    assert_response_code(200, response)
    stats[:trafficserver] = MultiJson.load(response.body).fetch("global").transform_values { |value| Integer(value, exception: false) || Float(value, exception: false) || value }

    response = Typhoeus.get("http://127.0.0.1:9444/connection-stats/", http_options)
    assert_response_code(200, response)
    stats[:api_backend] = MultiJson.load(response.body)

    stats[:client_to_nginx_router_active_connections_per_nginx_router] = stats.fetch(:nginx_router).fetch("connections_active")
    stats[:client_to_nginx_router_idle_connections_per_nginx_router] = stats.fetch(:nginx_router).fetch("connections_waiting")
    stats[:client_to_nginx_router_writing_connections_per_nginx_router] = stats.fetch(:nginx_router).fetch("connections_writing")
    stats[:nginx_router_to_trafficserver_active_connections_per_trafficserver] = stats.fetch(:trafficserver).fetch("proxy.process.http.current_client_connections")
    stats[:trafficserver_to_envoy_active_connections_per_trafficserver] = stats.fetch(:trafficserver).fetch("proxy.process.http.current_server_connections")
    stats[:trafficserver_to_envoy_active_connections_per_envoy] = stats.fetch(:envoy).fetch("http.router.downstream_cx_active")
    stats[:trafficserver_to_envoy_destroy_local_connections_per_envoy] = stats.fetch(:envoy).fetch("http.router.downstream_cx_destroy_local")
    stats[:trafficserver_to_envoy_destroy_remote_connections_per_envoy] = stats.fetch(:envoy).fetch("http.router.downstream_cx_destroy_remote")
    stats[:envoy_to_api_backend_active_connections_per_envoy] = stats.fetch(:envoy).fetch("cluster.api-backend-cluster-#{@@api_backend.id}.upstream_cx_active")
    stats[:envoy_to_api_backend_destroy_local_connections_per_envoy] = stats.fetch(:envoy).fetch("cluster.api-backend-cluster-#{@@api_backend.id}.upstream_cx_destroy_local")
    stats[:envoy_to_api_backend_destroy_remote_connections_per_envoy] = stats.fetch(:envoy).fetch("cluster.api-backend-cluster-#{@@api_backend.id}.upstream_cx_destroy_remote")
    stats[:envoy_to_api_backend_active_connections_per_api_backend] = stats.fetch(:api_backend).fetch("connections_active")
    stats[:envoy_to_api_backend_idle_connections_per_api_backend] = stats.fetch(:api_backend).fetch("connections_waiting")
    stats[:envoy_to_api_backend_writing_connections_per_api_backend] = stats.fetch(:api_backend).fetch("connections_writing")

    stats
  end

  def saturate_connections(path, num_requests:, max_concurrency:)
    hydra = Typhoeus::Hydra.new(max_concurrency: max_concurrency)
    requests = Array.new(num_requests) do
      request = Typhoeus::Request.new("http://127.0.0.1:9080#{path}", http_options)
      hydra.queue(request)
      request
    end
    hydra.run
    assert_equal(num_requests, requests.length)
    requests.each do |req|
      assert_response_code(200, req.response)
    end
  end
end

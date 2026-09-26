require_relative "../test_helper"

class Test::Proxy::TestTimeoutsConnect < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include Minitest::Hooks

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
          "proxy_send_timeout" => 10,
        },
      })
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_quick_timeout_when_backends_down
    prepend_api_backends([
      {
        :frontend_host => "127.0.0.1",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9450 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/down", :backend_prefix => "/down" }],
      },
    ]) do
      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/down", http_options)

      assert_response_code(503, response)
      assert_operator(response.total_time, :<, 1)
    end
  end

  # We test to ensure slow-responding responses do not hit the connection
  # timeout. Connection timeouts should only be hit in the event the connection
  # itself is slow to respond, but that's hard to test against (since the
  # underlying server in these cases is up). So for now, we're just going to
  # assume connection timeouts work as expected.
  def test_connect_timeout_get
    connect_timeout = $config["nginx"]["proxy_connect_timeout"]
    read_timeout = $config["nginx"]["proxy_read_timeout"]
    delay = connect_timeout + 2
    assert_operator(delay, :<, read_timeout)

    response = Typhoeus.get("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options)
    assert_response_code(200, response)
    assert_operator(response.total_time, :>, connect_timeout - BUFFER_TIME_LOWER)
  end

  def test_connect_timeout_post
    connect_timeout = $config["nginx"]["proxy_connect_timeout"]
    read_timeout = $config["nginx"]["proxy_read_timeout"]
    delay = connect_timeout + 2
    assert_operator(delay, :<, read_timeout)

    response = Typhoeus.post("http://127.0.0.1:9080/api/delay-sec/#{delay}", http_options)
    assert_response_code(200, response)
    assert_operator(response.total_time, :>, connect_timeout - BUFFER_TIME_LOWER)
  end
end

require_relative "../../test_helper"

class Test::Proxy::KeepAlive::TestClientSide < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_reuses_connections
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options.merge(:verbose => true))
    assert_response_code(200, response)

    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options.merge(:verbose => true))
    assert_response_code(200, response)

    # Ensure that curl's debug output contains the indicator of re-using a
    # keepalive connection.
    assert_match("Re-using existing http: connection", response.debug_info.text.join(""))
  end

  def test_timeout_is_configurable
    override_config({
      :nginx => {
        # Test 0 seconds to disable keepalive.
        :keepalive_timeout => 0,
      },
    }) do
      response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options.merge(:verbose => true))
      assert_response_code(200, response)

      response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options.merge(:verbose => true))
      assert_response_code(200, response)

      # Since keepalive is disabled, ensure that curl's debug output does not
      # contain the indicator of re-using a keepalive connection.
      refute_match("Re-using existing http: connection", response.debug_info.text.join(""))
    end
  end
end

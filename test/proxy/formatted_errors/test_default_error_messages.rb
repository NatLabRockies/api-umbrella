require_relative "../../test_helper"

class Test::Proxy::FormattedErrors::TestDefaultErrorMessages < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  parallelize_me!

  def setup
    super
    setup_server
  end

  def test_api_key_missing_message
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", keyless_http_options)
    assert_response_code(403, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "error" => {
        "code" => "API_KEY_MISSING",
        "message" => "No api_key was supplied. Get one at http://127.0.0.1:9080",
      },
    }, data)
  end

  def test_api_key_invalid_message
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", keyless_http_options.deep_merge({
      :headers => {
        "X-Api-Key" => "invalid",
      },
    }))
    assert_response_code(403, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "error" => {
        "code" => "API_KEY_INVALID",
        "message" => "An invalid api_key was supplied. Get one at http://127.0.0.1:9080",
      },
    }, data)
  end

  def test_api_key_disabled_message
    user = FactoryBot.create(:api_user, :disabled_at => Time.now.utc)
    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", keyless_http_options.deep_merge({
      :headers => {
        "X-Api-Key" => user.api_key,
      },
    }))
    assert_response_code(403, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "error" => {
        "code" => "API_KEY_DISABLED",
        "message" => "The api_key supplied has been disabled. Contact us for assistance: http://127.0.0.1:9080",
      },
    }, data)
  end
end

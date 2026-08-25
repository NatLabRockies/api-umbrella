require_relative "../../test_helper"

class Test::Proxy::RequestRewriting::TestStripsApiKeysWhenOptional < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  parallelize_me!

  def setup
    super
    setup_server
    once_per_class_setup do
      prepend_api_backends([
        {
          :frontend_host => "127.0.0.1",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/api-keys-optional/", :backend_prefix => "/" }],
          :settings => {
            :disable_api_key => true,
          },
        },
      ])
    end
  end

  def test_sanity_check_api_keys_optional
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/api-keys-optional/info/", keyless_http_options)
    assert_response_code(200, response)
  end

  def test_strips_api_key_from_header
    assert(http_options[:headers]["X-Api-Key"])
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/api-keys-optional/info/", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    refute(data["headers"]["x-api-key"])
  end

  def test_strips_api_key_from_query
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/api-keys-optional/info/?api_key=#{self.api_key}", keyless_http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({}, data["url"]["query"])
  end

  def test_strips_api_key_from_basic_auth
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/api-keys-optional/info/", keyless_http_options.deep_merge({
      :userpwd => "#{self.api_key}:",
    }))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    refute(data["basic_auth_username"])
    refute(data["headers"]["authorization"])
  end

  # FIXME: This situation of a key being passed along in http basic auth even
  # when not required currently triggers a 403 (since the gatekeeper assumes
  # the username is a key which then isn't valid). I don't think this is the
  # behavior we want, so need to figure out how to address this.
  def test_retains_basic_auth_if_api_key_passed_by_other_means
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/api-keys-optional/info/", keyless_http_options.deep_merge({
      :userpwd => "foo:",
    }))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal("foo", data["basic_auth_username"])
    assert(data["headers"]["authorization"])
  end
end

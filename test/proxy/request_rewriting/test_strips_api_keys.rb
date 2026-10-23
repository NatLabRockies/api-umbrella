require_relative "../../test_helper"

class Test::Proxy::RequestRewriting::TestStripsApiKeys < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  parallelize_me!

  def setup
    super
    setup_server
  end

  def test_strips_api_key_from_header
    assert(http_options[:headers]["X-Api-Key"])
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    refute(data["headers"]["x-api-key"])
  end

  def test_strips_api_key_from_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?api_key=#{self.api_key}", keyless_http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({}, data["url"]["query"])
  end

  def test_strips_api_key_from_start_of_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?api_key=#{self.api_key}&test=value", keyless_http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "test" => "value" }, data["url"]["query"])
  end

  def test_strips_api_key_from_end_of_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?test=value&api_key=#{self.api_key}", keyless_http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "test" => "value" }, data["url"]["query"])
  end

  def test_strips_api_key_from_middle_of_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?test=value&api_key=#{self.api_key}&foo=bar", keyless_http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "test" => "value", "foo" => "bar" }, data["url"]["query"])
    assert_equal("http://127.0.0.1/info/?test=value&foo=bar", data["raw_url"])
  end

  def test_strips_repeated_api_key_in_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?api_key=#{self.api_key}&api_key=foo&test=value&api_key=bar", keyless_http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "test" => "value" }, data["url"]["query"])
  end

  def test_strips_invalid_api_key_in_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?api_key=oops_typo_incorrect_api_key&test=value", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "test" => "value" }, data["url"]["query"])
  end

  def test_strips_empty_api_key_from_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?api_key=&test=value", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "test" => "value" }, data["url"]["query"])
  end

  def test_strips_boolean_value_api_key_from_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?api_key&test=value&foo", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "test" => "value", "foo" => true }, data["url"]["query"])
  end

  def test_strips_api_key_from_invalid_encoded_query
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?test=foo%26%20bar&url=%ED%A1%BC&api_key=#{self.api_key}", keyless_http_options)
    assert_response_code(200, response)
    data = JSON.parse(response.body)
    assert_equal({ "url" => "\xED\xA1\xBC", "test" => "foo& bar" }, data["url"]["query"])
  end

  def test_strips_api_key_from_basic_auth
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", keyless_http_options.deep_merge({
      :userpwd => "#{self.api_key}:",
    }))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    refute(data["basic_auth_username"])
    refute(data["headers"]["authorization"])
  end

  def test_retains_basic_auth_if_api_key_passed_by_other_means
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options.deep_merge({
      :userpwd => "foo:",
    }))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal("foo", data["basic_auth_username"])
    assert(data["headers"]["authorization"])
  end

  def test_retains_api_key_string_in_values
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?search=api_key", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "search" => "api_key" }, data["url"]["query"])
  end

  def test_retains_api_key_string_in_values_with_prefix
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?search=foo_api_key", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "search" => "foo_api_key" }, data["url"]["query"])
  end

  def test_retains_api_key_string_in_values_with_suffix
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?search=api_key_foo", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "search" => "api_key_foo" }, data["url"]["query"])
  end

  def test_retains_api_key_string_in_param_with_prefix
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?foo_api_key=bar", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "foo_api_key" => "bar" }, data["url"]["query"])
  end

  def test_retains_api_key_string_in_param_with_suffix
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?api_key_foo=bar", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({ "api_key_foo" => "bar" }, data["url"]["query"])
  end

  def test_preserves_query_string_order
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/?ccc=foo&aaa=bar&api_key=#{self.api_key}&b=test", http_options)
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal("http://127.0.0.1/info/?ccc=foo&aaa=bar&b=test", data["raw_url"])
  end
end

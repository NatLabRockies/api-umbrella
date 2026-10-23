require_relative "../../test_helper"

class Test::Proxy::Logging::TestAnalyticsCustomFields < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Logging

  parallelize_me!

  def setup
    super
    setup_server
  end

  def test_custom_field1
    response = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom1" => unique_test_id,
        },
      }),
    }))
    assert_response_code(200, response)
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom1"])

    record = wait_for_log(response)[:hit_source]
    assert_equal(unique_test_id, record.fetch("response_custom1"))
    assert_nil(record["response_custom2"])
    assert_nil(record["response_custom3"])
  end

  def test_custom_field2
    response = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom2" => unique_test_id,
        },
      }),
    }))
    assert_response_code(200, response)
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom2"])

    record = wait_for_log(response)[:hit_source]
    assert_nil(record["response_custom1"])
    assert_equal(unique_test_id, record.fetch("response_custom2"))
    assert_nil(record["response_custom3"])
  end

  def test_custom_field3
    response = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom3" => unique_test_id,
        },
      }),
    }))
    assert_response_code(200, response)
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom3"])

    record = wait_for_log(response)[:hit_source]
    assert_nil(record["response_custom1"])
    assert_nil(record["response_custom2"])
    assert_equal(unique_test_id, record.fetch("response_custom3"))
  end

  def test_all_custom_fields
    response = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom1" => "hello",
          "X-Api-Umbrella-Analytics-Custom2" => "world",
          "X-Api-Umbrella-Analytics-Custom3" => "!",
        },
      }),
    }))
    assert_response_code(200, response)
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom1"])
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom2"])
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom3"])

    record = wait_for_log(response)[:hit_source]
    assert_equal("hello", record.fetch("response_custom1"))
    assert_equal("world", record.fetch("response_custom2"))
    assert_equal("!", record.fetch("response_custom3"))
  end

  def test_truncates_values_to_400_chars
    response = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom1" => "A" * 500,
          "X-Api-Umbrella-Analytics-Custom2" => "B" * 500,
          "X-Api-Umbrella-Analytics-Custom3" => "C" * 500,
        },
      }),
    }))
    assert_response_code(200, response)
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom1"])
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom2"])
    assert_nil(response.headers["X-Api-Umbrella-Analytics-Custom3"])

    record = wait_for_log(response)[:hit_source]
    assert_equal("A" * 400, record.fetch("response_custom1"))
    assert_equal("B" * 400, record.fetch("response_custom2"))
    assert_equal("C" * 400, record.fetch("response_custom3"))
  end

  def test_does_nothing_with_unknown_custom_fields
    response = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom0" => "custom0",
          "X-Api-Umbrella-Analytics-Custom4" => "custom4",
        },
      }),
    }))
    assert_response_code(200, response)
    assert_equal("custom0", response.headers["X-Api-Umbrella-Analytics-Custom0"])
    assert_equal("custom4", response.headers["X-Api-Umbrella-Analytics-Custom4"])

    record = wait_for_log(response)[:hit_source]
    refute_match("custom0", MultiJson.dump(record))
    refute_match("custom4", MultiJson.dump(record))
  end

  def test_custom_fields_on_cached_responses
    response1 = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/#{unique_test_id}", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom1" => "#{unique_test_id}-1",
          "Cache-Control" => "max-age=60",
        },
      }),
    }))
    assert_response_code(200, response1)
    assert_equal("MISS", response1.headers.fetch("X-Cache"))
    assert_equal("http/1.1 api-umbrella (ApacheTrafficServer [cMsSfW])", response1.headers.fetch("Via"))
    assert(response1.headers.fetch("X-Api-Umbrella-Request-ID"))
    assert_nil(response1.headers["X-Api-Umbrella-Analytics-Custom1"])

    result1 = wait_for_log(response1)
    record1 = result1.fetch(:hit_source)
    assert_equal("#{unique_test_id}-1", record1.fetch("response_custom1"))
    assert_nil(record1["response_custom2"])
    assert_nil(record1["response_custom3"])
    assert_equal("MISS", record1.fetch("response_cache"))
    assert_equal("cMsSfW", record1.fetch("response_cache_flags"))
    assert_equal(response1.headers.fetch("X-Api-Umbrella-Request-ID"), result1.fetch(:hit).fetch("_id"))

    response2 = Typhoeus.get("http://127.0.0.1:9080/api/set-http-response-headers/#{unique_test_id}", log_http_options.deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        "http_response_headers" => {
          "X-Api-Umbrella-Analytics-Custom1" => "#{unique_test_id}-2",
          "Cache-Control" => "Cache-Control: max-age=60",
        },
      }),
    }))
    assert_response_code(200, response2)
    assert_equal("HIT", response2.headers.fetch("X-Cache"))
    assert_equal("http/1.1 api-umbrella (ApacheTrafficServer [cRs f ])", response2.headers.fetch("Via"))
    assert(response2.headers.fetch("X-Api-Umbrella-Request-ID"))
    refute_equal(response1.headers.fetch("X-Api-Umbrella-Request-ID"), response2.headers.fetch("X-Api-Umbrella-Request-ID"))
    assert_nil(response2.headers["X-Api-Umbrella-Analytics-Custom1"])

    result2 = wait_for_log(response2)
    record2 = result2.fetch(:hit_source)
    assert_equal("#{unique_test_id}-1", record2.fetch("response_custom1"))
    assert_nil(record2["response_custom2"])
    assert_nil(record2["response_custom3"])
    assert_equal("HIT", record2.fetch("response_cache"))
    assert_equal("cRs f ", record2.fetch("response_cache_flags"))
    assert_equal(response2.headers.fetch("X-Api-Umbrella-Request-ID"), result2.fetch(:hit).fetch("_id"))
  end
end

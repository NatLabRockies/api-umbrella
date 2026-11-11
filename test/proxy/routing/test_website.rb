require_relative "../../test_helper"

class Test::Proxy::Routing::TestWebsite < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  parallelize_me!

  def setup
    super
    setup_server
  end

  def test_default_website
    response = Typhoeus.get("https://127.0.0.1:9081/", keyless_http_options)
    assert_response_code(200, response)
    assert_match("Your API Site Name", response.body)

    response = Typhoeus.get("https://127.0.0.1:9081/signup/", keyless_http_options)
    assert_response_code(200, response)
    assert_match("API Key Sign Up", response.body)
  end

  def test_https_redirect
    response = Typhoeus.get("http://127.0.0.1:9080/", keyless_http_options)
    assert_response_code(301, response)
    assert_equal("https://127.0.0.1:9081/", response.headers["location"])

    response = Typhoeus.get("http://127.0.0.1:9080/signup/", keyless_http_options)
    assert_response_code(301, response)
    assert_equal("https://127.0.0.1:9081/signup/", response.headers["location"])
  end

  def test_signup_https_redirect_wildcard_host
    response = Typhoeus.get("http://127.0.0.1:9080/signup/", keyless_http_options.deep_merge({
      :headers => {
        "Host" => "unknown.foo",
      },
    }))
    assert_response_code(301, response)
    assert_equal("https://unknown.foo:9081/signup/", response.headers["location"])
  end

  def test_signup_missing_trailing_slash
    http_opts = keyless_http_options

    response = Typhoeus.get("http://127.0.0.1:9080/signup", http_opts)
    assert_response_code(301, response)
    assert_equal("https://127.0.0.1:9081/signup", response.headers["location"])

    response = Typhoeus.get("https://127.0.0.1:9081/signup", http_opts)
    assert_response_code(301, response)
    assert_equal("http://127.0.0.1:9080/signup/", response.headers["location"])
  end

  def test_signup_missing_trailing_slash_wildcard_host
    http_opts = keyless_http_options.deep_merge({
      :headers => {
        "Host" => "unknown.foo",
      },
    })

    response = Typhoeus.get("http://127.0.0.1:9080/signup", http_opts)
    assert_response_code(301, response)
    assert_equal("https://unknown.foo:9081/signup", response.headers["location"])

    response = Typhoeus.get("https://127.0.0.1:9081/signup", http_opts)
    assert_response_code(301, response)
    assert_equal("http://unknown.foo:9080/signup/", response.headers["location"])
  end
end

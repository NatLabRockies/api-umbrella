require_relative "../test_helper"

# Since sending empty HTTP header values is a bit funky in curl and Typhoeus,
# perform some sanity checks on our `empty_http_header_options` helper to
# ensure that it actually does what we think it does.
class Test::TestingSanityChecks::TestEmptyHttpHeaders < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  parallelize_me!

  def setup
    super
    setup_server
  end

  def test_empty_http_header_helper
    http_opts = http_options.merge(:verbose => true)
    http_opts.deep_merge!(empty_http_header_options("X-Foo"))
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_opts)
    assert_response_code(200, response)

    # Verify that the empty header was sent by curl.
    header_out = response.debug_info.header_out.join("")
    assert_match("\r\nX-Foo:\r\n", header_out)

    # Extra sanity check to see if the header made its way to the backend.
    data = MultiJson.load(response.body)
    assert_equal("", data["headers"]["x-foo"])
  end

  def test_multiple_empty_headers
    http_opts = http_options.merge(:verbose => true)
    http_opts.deep_merge!(empty_http_header_options("X-Foo"))
    http_opts.deep_merge!(empty_http_header_options("X-Bar"))
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_opts)
    assert_response_code(200, response)

    # Verify that the empty header was sent by curl.
    header_out = response.debug_info.header_out.join("")
    assert_match("\r\nX-Foo:\r\n", header_out)
    assert_match("\r\nX-Bar:\r\n", header_out)

    # Extra sanity check to see if the header made its way to the backend.
    data = MultiJson.load(response.body)
    assert_equal("", data["headers"]["x-foo"])
    assert_equal("", data["headers"]["x-bar"])
  end

  def test_overrides_default_header
    http_opts = http_options.merge(:verbose => true)
    http_opts.deep_merge!(empty_http_header_options("Content-Type"))
    response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_opts)
    assert_response_code(200, response)

    # Verify that the empty header was sent by curl.
    header_out = response.debug_info.header_out.join("")
    assert_match("\r\nContent-Type:\r\n", header_out)

    # Extra sanity check to see if the header made its way to the backend.
    data = MultiJson.load(response.body)
    assert_equal("", data["headers"]["content-type"])
  end
end

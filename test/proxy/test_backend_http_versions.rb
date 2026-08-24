require_relative "../test_helper"

# Tests to see how different HTTP client version request get translated into
# HTTP requests for the API backend proxied requests.
#
# Currently, these all get translated to HTTP 1.1 requests (since nginx doesn't
# currently support 2.0 upstream requests:
# https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_http_version),
# but if this changes in the behavior, we can update these tests (this is
# mostly just about documenting current behavior).
#
# This uses Caddy as an API backend server, since it supports HTTP versions
# 1-3. The current version of curl inside our image doesn't yet support HTTP
# v3, though, so we don't have tests for that yet.
class Test::Proxy::TestBackendHttpVersions < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  parallelize_me!

  def setup
    super
    setup_server
    once_per_class_setup do
      prepend_api_backends([
        {
          :frontend_host => "127.0.0.1",
          :backend_host => "localhost",
          :servers => [{ :host => "127.0.0.1", :port => $config["caddy"]["http_port"] }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/http/", :backend_prefix => "/" }],
        },
        {
          :frontend_host => "127.0.0.1",
          :backend_host => "localhost",
          :backend_protocol => "https",
          :servers => [{ :host => "127.0.0.1", :port => $config["caddy"]["https_port"] }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/https/", :backend_prefix => "/" }],
        },
      ])
    end
  end

  def test_httpv1_0_client
    # Make to HTTP server port, since current version of curl doesn't seem to
    # work with HTTP 1.0 without `--no-alpn` option, which Typhoeus doesn't
    # currently support.
    http_opts = http_options.merge(ssl_verifypeer: false, http_version: :httpv1_0)
    response = Typhoeus.get("http://localhost:#{$config["caddy"]["http_port"]}/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.0 200 OK", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.0", data.fetch("http.request.proto"))

    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/http/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200 OK", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))

    response = Typhoeus.get("https://127.0.0.1:9081/#{unique_test_class_id}/http/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200 OK", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))
  end

  def test_httpv1_1_client
    http_opts = http_options.merge(ssl_verifypeer: false, http_version: :httpv1_1)
    response = Typhoeus.get("https://localhost:#{$config["caddy"]["https_port"]}/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200 OK", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))

    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200 OK", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))

    response = Typhoeus.get("https://127.0.0.1:9081/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200 OK", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))
  end

  def test_httpv2_0_client
    http_opts = http_options.merge(ssl_verifypeer: false, http_version: :httpv2_0)
    response = Typhoeus.get("https://localhost:#{$config["caddy"]["https_port"]}/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/2 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/2.0", data.fetch("http.request.proto"))

    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))

    response = Typhoeus.get("https://127.0.0.1:9081/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))
  end

  def test_httpv2_tls_client
    http_opts = http_options.merge(ssl_verifypeer: false, http_version: :httpv2_tls)
    response = Typhoeus.get("https://localhost:#{$config["caddy"]["https_port"]}/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/2 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/2.0", data.fetch("http.request.proto"))

    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))

    response = Typhoeus.get("https://127.0.0.1:9081/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))
  end

  def test_httpv2_prior_knowledge_client
    http_opts = http_options.merge(ssl_verifypeer: false, http_version: :httpv2_prior_knowledge)
    response = Typhoeus.get("https://localhost:#{$config["caddy"]["https_port"]}/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/2 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/2.0", data.fetch("http.request.proto"))

    # The curl `--http2-prior-knowledge` flag doesn't make sense over http,
    # since http2 requires https.
    #
    # This previously returned a response in openresty 1.27.1.2, but the
    # upgrade to 1.29.2.3 changed this behavior. I'm not sure what specific
    # version changed this, but I think the new behavior actually makese more
    # sense.
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(0, response)
    assert_equal(:got_nothing, response.return_code)

    response = Typhoeus.get("https://127.0.0.1:9081/#{unique_test_class_id}/https/", http_opts)
    assert_response_code(200, response)
    assert_match("HTTP/1.1 200", response.response_headers)
    data = MultiJson.load(response.body)
    assert_equal("HTTP/1.1", data.fetch("http.request.proto"))
  end
end

require_relative "../../test_helper"

class Test::Proxy::Envoy::TestHttpProxy < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Logging

  def setup
    super
    setup_server
  end

  def test_disabled_by_default
    assert_raises Errno::ECONNREFUSED do
      Socket.tcp("127.0.0.1", 13002, connect_timeout: 5)
    end
  end

  def test_only_allows_specified_domains
    http_options = {
      :proxy => "http://127.0.0.1:13002",
    }

    override_config({
      "envoy" => {
        "http_proxy" => {
          "enabled" => true,
          "allowed_domains" => ["example.com", "www.example.org:443"],
        },
      },
    }) do
      open = Socket.tcp("127.0.0.1", 13002, connect_timeout: 5) { true }
      assert_equal(true, open)

      response = Typhoeus.get("http://example.com/", http_options)
      assert_response_code(200, response)

      response = Typhoeus.get("https://example.com/", http_options)
      assert_response_code(0, response)
      assert_equal(:recv_error, response.return_code)
      assert_match("403 Forbidden", response.response_headers)

      response = Typhoeus.get("http://www.example.com/", http_options)
      assert_response_code(403, response)

      response = Typhoeus.get("https://www.example.com/", http_options)
      assert_response_code(0, response)
      assert_equal(:recv_error, response.return_code)
      assert_match("403 Forbidden", response.response_headers)

      response = Typhoeus.get("http://example.org/", http_options)
      assert_response_code(403, response)

      response = Typhoeus.get("https://example.org/", http_options)
      assert_response_code(0, response)
      assert_equal(:recv_error, response.return_code)
      assert_match("403 Forbidden", response.response_headers)

      response = Typhoeus.get("http://www.example.org/", http_options)
      assert_response_code(403, response)

      response = Typhoeus.get("https://www.example.org/", http_options)
      assert_response_code(200, response)

      response = Typhoeus.get("http://google.com/", http_options)
      assert_response_code(403, response)

      response = Typhoeus.get("https://google.com/", http_options)
      assert_response_code(0, response)
      assert_equal(:recv_error, response.return_code)
      assert_match("403 Forbidden", response.response_headers)
    end
  end

  def test_opensearch_requests_use_proxy
    override_config({
      "http_proxy" => "http://127.0.0.1:13002",
      "https_proxy" => "http://127.0.0.1:13002",
      "envoy" => {
        "http_proxy" => {
          "enabled" => true,
          "allowed_domains" => ["opensearch:9200"],
        },
      },
    }) do
      log_tail = LogTail.new("envoy/http_proxy_access.log")

      response = Typhoeus.get("https://127.0.0.1:9081/api/hello", log_http_options)
      assert_response_code(200, response)
      request_id = response.headers["X-Api-Umbrella-Request-ID"]

      record = wait_for_log(response)[:hit_source]
      assert_equal("/api/hello", record["request_path"])

      # Fluent Bit establishes a CONNECT tunnel for its proxying, so the only
      # thing being logged in the HTTP access log is the initial CONNECT
      # request. So we won't actually see the /_bulk requests being sent over
      # this tunnel. Also send a SIGHUP to fluent-bit, since otherwise it seems
      # like it can take a while for this CONNECT request to be flushed to the
      # logs (probably since it's a persistent tunnel).
      api_umbrella_process.perp_signal("fluent-bit", "hup")
      log_output = log_tail.read_until(%r{"original":"Fluent-Bit"})
      log = MultiJson.load(log_output.scan(%r{^.*"original":"Fluent-Bit".*$}).last)
      assert_nil(log["uri"])
      assert_equal("opensearch:9200", log.fetch("url").fetch("domain"))
      assert_equal("http", log.fetch("url").fetch("scheme"))
      assert_equal("CONNECT", log.fetch("http").fetch("request").fetch("method"))
      assert_equal(200, log.fetch("http").fetch("response").fetch("status_code"))
      assert_match(/\A[0-9a-f.:]+:9200\z/, log.fetch("up_addr"))
      assert_nil(log["up_tls_ver"])
      assert_equal("Fluent-Bit", log.fetch("user_agent").fetch("original"))

      response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
        :params => {
          "start_at" => (Time.now - (60 * 60 * 24 * 2)).to_date.iso8601,
          "end_at" => (Time.now + (60 * 60 * 24 * 2)).to_date.iso8601,
          "interval" => "day",
          "start" => "0",
          "length" => "10",
          "query" => MultiJson.dump({
            "condition" => "AND",
            "rules" => [{
              "id" => "request_id",
              "field" => "request_id",
              "type" => "string",
              "input" => "text",
              "operator" => "equal",
              "value" => request_id,
            }],
          }),
        },
      }))

      assert_response_code(200, response)
      data = MultiJson.load(response.body)
      assert_equal(1, data["recordsTotal"])
      assert_equal(request_id, data["data"][0]["request_id"])

      log_output = log_tail.read_until(%r{"uri":"/_msearch"})
      log = MultiJson.load(log_output.scan(%r{^.*"uri":"/_msearch".*$}).last)
      assert_equal("/_msearch", log.fetch("url").fetch("original"))
      assert_equal("opensearch:9200", log.fetch("url").fetch("domain"))
      assert_equal("http", log.fetch("url").fetch("scheme"))
      assert_equal("POST", log.fetch("http").fetch("request").fetch("method"))
      assert_equal(200, log.fetch("http").fetch("response").fetch("status_code"))
      assert_match(/\A[0-9a-f.:]+:9200\z/, log.fetch("up_addr"))
      assert_nil(log["up_tls_ver"])
      assert_match("lua-resty-http", log.fetch("user_agent").fetch("original"))
    end
  end

  def test_geoip_requests_use_proxy
    geoip_path = File.join($config.fetch("db_dir"), "geoip/GeoLite2-City.mmdb")
    FileUtils.rm_f(geoip_path)

    override_config({
      "http_proxy" => "http://127.0.0.1:13002",
      "https_proxy" => "http://127.0.0.1:13002",
      "envoy" => {
        "http_proxy" => {
          "enabled" => true,
          "allowed_domains" => [
            "opensearch:9200",
            "download.maxmind.com:443",
          ],
        },
      },
      "geoip" => {
        "db_path" => geoip_path,
        "maxmind_license_key" => "invalid-test",
      },
    }) do
      log_tail = LogTail.new("envoy/http_proxy_access.log")

      # Trigger another reload after the Envoy proxy is up, since the first
      # attempts to download geoip data from the initial `override_config` will
      # fail because the proxy isn't up at reload time. We'll assume this won't
      # be a production issue, where the proxy should be more persistent and up
      # beforehand.
      reload_stderr = Tempfile.new
      api_umbrella_process.reload(stderr: reload_stderr)
      reload_stderr.close
      reload_stderr = File.read(reload_stderr.path)

      assert_match("https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&suffix=tar.gz&license_key=invalid-test", reload_stderr)
      assert_match("curl: (22) The requested URL returned error: 401", reload_stderr)

      log_output = log_tail.read_until(%r{"method":"CONNECT"})
      log = MultiJson.load(log_output.scan(%r{^.*"method":"CONNECT".*$}).last)
      assert_nil(log["uri"])
      assert_equal("download.maxmind.com:443", log.fetch("url").fetch("domain"))
      assert_equal("http", log.fetch("url").fetch("scheme"))
      assert_equal("CONNECT", log.fetch("http").fetch("request").fetch("method"))
      assert_equal(200, log.fetch("http").fetch("response").fetch("status_code"))
      assert_match(/\A[0-9a-f.:]+:443\z/, log.fetch("up_addr"))
      assert_nil(log["up_tls_ver"])
      assert_match("curl", log.fetch("user_agent").fetch("original"))
      assert_equal("downstream_remote_disconnect", log.fetch("resp_detail"))
    end
  end
end

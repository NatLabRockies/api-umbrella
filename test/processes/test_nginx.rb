require_relative "../test_helper"

class Test::Processes::TestNginx < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Logging

  def setup
    super
    setup_server
  end

  def test_nginx_logging
    # Default file-based logging.
    access_log_tail = LogTail.new("nginx/access.log")

    response = Typhoeus.get("http://127.0.0.1:9080/api/hello?foo=bar", http_options)

    access_log = access_log_tail.read_until(response.headers["X-Api-Umbrella-Request-ID"], timeout: 30)
    log_line = access_log.match(/^.*#{response.headers["X-Api-Umbrella-Request-ID"]}.*$/)[0]
    log_row = MultiJson.load(log_line)
    assert_equal("200", log_row.fetch("http").fetch("response").fetch("status_code"))
    assert_equal(response.headers["X-Api-Umbrella-Request-ID"], log_row.fetch("http").fetch("request").fetch("id"))
    assert_equal("200", log_row.fetch("up_status"))

    # Check stdout/stderr based logging.
    override_config({
      "log" => {
        "destination" => "console",
      },
    }) do
      current_log_tail = LogTail.new("nginx/current")

      response = Typhoeus.get("http://127.0.0.1:9080/api/hello?foo=bar", http_options)

      current_log = current_log_tail.read_until(response.headers["X-Api-Umbrella-Request-ID"], timeout: 30)
      log_line = current_log.match(/^.*#{response.headers["X-Api-Umbrella-Request-ID"]}.*$/)[0]
      # Remove the timestamp prefix from the log line.
      #
      # When really outputting to stdout, this won't happen (since gawk won't
      # append it for JSON line), but in this test environment, stdout is still
      # being output to svlogd because we haven't fully restarted perp and the
      # regenerated the rc.log file.
      log_line = log_line.split(" ", 2).last
      log_row = MultiJson.load(log_line)
      assert_equal("200", log_row.fetch("http").fetch("response").fetch("status_code"))
      assert_equal(response.headers["X-Api-Umbrella-Request-ID"], log_row.fetch("http").fetch("request").fetch("id"))
      assert_equal("200", log_row.fetch("up_status"))
    end
  end
end

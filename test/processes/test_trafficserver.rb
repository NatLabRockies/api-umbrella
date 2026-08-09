require_relative "../test_helper"

class Test::Processes::TestTrafficserver < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Logging

  def setup
    super
    setup_server
  end

  def test_trafficserver_logging
    # Default file-based logging.
    access_log_tail = LogTail.new("trafficserver/access.log")

    response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options)

    access_log = access_log_tail.read_until(response.headers["X-Api-Umbrella-Request-ID"], timeout: 30)
    log_line = access_log.match(/^.*#{response.headers["X-Api-Umbrella-Request-ID"]}.*$/)[0]
    log_row = MultiJson.load(log_line)
    assert_equal("200", log_row.fetch("status"))
    assert_equal(response.headers["X-Api-Umbrella-Request-ID"], log_row.fetch("id"))
    assert_equal("200", log_row.fetch("up_status"))

    log_glob = File.join($config["log_dir"], "trafficserver/*.{log,out,old}")
    log_paths = Dir.glob(log_glob)
    log_filenames = log_paths.map { |path| File.basename(path) }
    assert_includes(log_filenames, "access.log")
    assert_includes(log_filenames, "diags.log")
    FileUtils.rm_f(log_paths)

    # Check stdout/stderr based logging.
    override_config({
      "log" => {
        "destination" => "console",
      },
    }) do
      current_log_tail = LogTail.new("trafficserver/current")

      response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options)

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
      assert_equal("200", log_row.fetch("status"))
      assert_equal(response.headers["X-Api-Umbrella-Request-ID"], log_row.fetch("id"))
      assert_equal("200", log_row.fetch("up_status"))

      log_paths = Dir.glob(log_glob)
      # Ignore crash log files, since the restart to set this setting may have
      # triggered an empty crash log file generation (even though there was no
      # actual crash).
      log_paths.reject! { |path| File.basename(path).start_with?("crash-") }
      assert_equal([], log_paths)
    end
  end

  def test_runs_crashlog
    output, status = run_shell("ps", "-e", "-o", "cmd")
    if status != 0
      raise "ps failed (status: #{status}): #{output}"
    end

    assert_match("traffic_server", output)
    assert_match("traffic_crashlog", output)
  end
end

require_relative "../test_helper"

class Test::Processes::TestFluentBit < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Logging

  def setup
    super
    setup_server
  end

  # To make sure fluent-bit doesn't leak memory while logging requests
  def test_memory_leak
    log_tail = LogTail.new("fluent-bit/current")

    # Make some initial requests, to ensure fluent-bit is warmed up, which should
    # stabilize its memory use.
    make_requests(2_000)
    warmed_memory_use = memory_use

    # Validate that the fluent-bit process isn't using more than 60MB initially.
    # If it is, then this is probably the best indicator that there's a memory
    # leak and previous tests in the test suite have already leaked a lot of
    # memory. Typically fluent-bit is more in the 10MB-30MB range.
    assert_operator(warmed_memory_use[:rss], :<, 60_000)

    # Make more requests.
    make_requests(10_000)
    final_memory_use = memory_use

    # Compare the memory use before and after making requests. Note that this
    # is a very loose test (allowing 15MB of growth), since there can be a
    # decent amount of fluctuation in normal use. It's hard to determine
    # whether there's really a leak in such a short test, so the better test is
    # actually the initial check to ensure the process is less than 60MB after
    # warmup. Assuming this test gets called as part of running the full test
    # suite, and it's not one of the initial tests (which is randomized, but
    # won't be at least enough times to catch this at some point), then that's
    # a better test for the leak, since it allows us to detect leaks over
    # longer periods of time (over the entire time the test suite is running,
    # rather than just in this isolated test).
    rss_diff = final_memory_use.fetch(:rss) - warmed_memory_use.fetch(:rss)
    assert_operator(rss_diff, :<=, 15_000)

    # Ensure nothing was generated in the opensearch error log file, since
    # the specific leak in v8.28.0 was triggered by generated error data.
    log = log_tail.read
    refute_match(/\[\s*error\s*\]/, log)
  end

  def test_opensearch_stdout_logs
    log_tail = LogTail.new("fluent-bit/current")

    response = Typhoeus.get("http://127.0.0.1:9080/api/hello/#{unique_test_id}", http_options)
    assert_response_code(200, response)

    log = log_tail.read_until(unique_test_id, timeout: 30)
    log_line = log.match(/^.*#{unique_test_id}.*$/)[0]
    # Remove the timestamp prefix from the log line.
    log_line = log_line.split(" ", 2).last
    log_row = MultiJson.load(log_line)
    assert_equal("/api/hello/#{unique_test_id}", log_row.fetch("request_path"))
    assert_equal(response.headers["X-Api-Umbrella-Request-ID"], log_row.fetch("request_id"))
    assert_match_iso8601(log_row.fetch("_log_timestamp"))
  end

  def test_opensearch_error_log
    make_opensearch_config_invalid do
      log_tail = LogTail.new("fluent-bit/current")

      response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options)
      assert_response_code(200, response)

      log = log_tail.read_until(/strict_dynamic_mapping_exception/, timeout: 30)

      # Expect the failed message in the log file.
      assert_match("[error] [output:opensearch:opensearch", log)
      assert_match(/strict_dynamic_mapping_exception.*dynamic introduction of \[flb-key\] within/, log)
    end
  end

  def test_opensearch_error_log_to_console
    override_config({
      "log" => {
        "destination" => "console",
      },
    }) do
      make_opensearch_config_invalid do
        log_tail = LogTail.new("fluent-bit/current")

        response = Typhoeus.get("http://127.0.0.1:9080/api/hello", http_options)
        assert_response_code(200, response)

        # Expect the failed message in the "current" log file, which is
        # actually what would be outputting to the real console if things were
        # started in this console mode.
        log = log_tail.read_until(/strict_dynamic_mapping_exception/, timeout: 30)
        assert_match("[error] [output:opensearch:opensearch", log)
        assert_match(/strict_dynamic_mapping_exception.*dynamic introduction of \[flb-key\] within/, log)
      end
    end
  end

  private

  def make_requests(count)
    request = nil
    hydra = Typhoeus::Hydra.new
    count.times do
      request = Typhoeus::Request.new("http://127.0.0.1:9080/api/hello/", log_http_options)
      hydra.queue(request)
    end
    hydra.run

    # Just check for the last request made and make sure it gets logged.
    assert_response_code(200, request.response)
    wait_for_log(request.response)
  end

  def memory_use
    pid = api_umbrella_process.perp_pid("fluent-bit")
    output, status = run_shell("ps", "-o", "vsz=,rss=", pid)
    assert_equal(0, status, output)

    columns = output.strip.split(/\s+/)
    assert_equal(2, columns.length, columns)

    memory = {
      :vsz => Integer(columns[0]),
      :rss => Integer(columns[1]),
    }

    assert_operator(memory[:vsz], :>, 0)
    assert_operator(memory[:rss], :>, 0)

    memory
  end

  def make_opensearch_config_invalid
    # Make a temporary change to the fluent-bit configuration to make the output
    # invalid.
    conf_path = File.join($config["etc_dir"], "fluent-bit/fluent-bit.yaml")
    content = YAML.safe_load_file(conf_path)
    FileUtils.mv(conf_path, "#{conf_path}.bak")

    # Trigger opensearch logging errors by using an invalid template.
    opensearch = content.fetch("pipeline").fetch("outputs").detect { |output| output.fetch("name") == "opensearch" }
    opensearch["include_tag_key"] = true

    # Write the new temp config file and restart fluent-bit.
    File.write(conf_path, YAML.safe_dump(content))
    api_umbrella_process.perp_restart("fluent-bit")

    yield
  ensure
    # Restore the original config file and restart.
    FileUtils.mv("#{conf_path}.bak", conf_path)
    api_umbrella_process.perp_restart("fluent-bit")
  end
end

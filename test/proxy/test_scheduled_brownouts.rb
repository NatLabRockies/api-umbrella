require_relative "../test_helper"

class Test::Proxy::TestScheduledBrownouts < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::Logging
  include Minitest::Hooks

  def setup
    super
    setup_server
    once_per_class_setup do
      prepend_api_backends([
        {
          :frontend_host => "active-brownout-all-paths.#{unique_test_class_hostname}",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/", :backend_prefix => "/" }],
        },
        {
          :frontend_host => "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/", :backend_prefix => "/" }],
        },
        {
          :frontend_host => ".dot-wildcard.#{unique_test_class_hostname}",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/dot-wildcard/", :backend_prefix => "/" }],
        },
        {
          :frontend_host => "dot-wildcard.#{unique_test_class_hostname}",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/dot-wildcard-root/", :backend_prefix => "/" }],
        },
        {
          :frontend_host => "foo.dot-wildcard.#{unique_test_class_hostname}",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/dot-wildcard-explicit-subdomain/", :backend_prefix => "/" }],
        },
        {
          :frontend_host => "custom-settings.#{unique_test_class_hostname}",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/", :backend_prefix => "/" }],
        },
        {
          :frontend_host => "overlap.#{unique_test_class_hostname}",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/", :backend_prefix => "/" }],
        },
      ])

      override_config_set({
        :nginx => {
          :server_names_hash_bucket_size => 128,
        },
        :hosts => [
          {
            :hostname => "active-brownout-all-paths.#{unique_test_class_hostname}",
            :scheduled_brownouts => [
              {
                :path_regex => ".*",
                :schedule => [
                  {
                    :start_time => Time.now.iso8601,
                    :end_time => (Time.now + 900).iso8601,
                  },
                ],
              },
            ],
          },
          {
            :hostname => "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
            :scheduled_brownouts => [
              {
                :path_regex => "(^/#{unique_test_class_id}/head.*|utf8)",
                :schedule => [
                  {
                    :start_time => Time.utc(2025, 1, 1).iso8601,
                    :end_time => Time.utc(2025, 1, 2).iso8601,
                  },
                  {
                    # Explicit time zone config.
                    :start_time => "2025-01-06T17:00:00-07:00",
                    :end_time => "2025-01-07T17:00:00-07:00",
                  },
                ],
              },
            ],
          },
          {
            :hostname => ".dot-wildcard.#{unique_test_class_hostname}",
            :scheduled_brownouts => [
              {
                :path_regex => ".*",
                :schedule => [
                  {
                    :start_time => Time.now.iso8601,
                    :end_time => (Time.now + 900).iso8601,
                  },
                ],
              },
            ],
          },
          {
            :hostname => "custom-settings.#{unique_test_class_hostname}",
            :scheduled_brownouts => [
              {
                :path_regex => ".*",
                :status_code => 403,
                :message => "Custom message",
                :schedule => [
                  {
                    :start_time => Time.now.iso8601,
                    :end_time => (Time.now + 900).iso8601,
                  },
                ],
              },
            ],
          },
          {
            :hostname => "overlap.#{unique_test_class_hostname}",
            :scheduled_brownouts => [
              {
                :path_regex => ".*",
                :message => "Overlap message 1",
                :schedule => [
                  {
                    :start_time => Time.utc(2025, 1, 1).iso8601,
                    :end_time => Time.utc(2025, 1, 2).iso8601,
                  },
                ],
              },
              {
                :path_regex => "info",
                :message => "Overlap message 2",
                :schedule => [
                  {
                    :start_time => Time.utc(2025, 1, 1).iso8601,
                    :end_time => Time.utc(2025, 1, 10).iso8601,
                  },
                ],
              },
              {
                :path_regex => ".*",
                :message => "Overlap message 3",
                :schedule => [
                  {
                    :start_time => Time.utc(2025, 1, 1).iso8601,
                    :end_time => Time.utc(2025, 1, 3).iso8601,
                  },
                ],
              },
            ],
          },
          {
            :hostname => "overlap.#{unique_test_class_hostname}",
            :scheduled_brownouts => [
              {
                :path_regex => "info",
                :message => "Overlap message 4",
                :schedule => [
                  {
                    :start_time => Time.utc(2025, 1, 1).iso8601,
                    :end_time => Time.utc(2025, 2, 10).iso8601,
                  },
                ],
              },
            ],
          },
        ],
      })
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_default_brownout_response
    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "active-brownout-all-paths.#{unique_test_class_hostname}",
    )
    data = MultiJson.load(response.body)
    assert_equal({
      "error" => {
        "code" => "SCHEDULED_BROWNOUT",
        "message" => "This API will be going away. Seek an alternative API. Contact us for assistance: https://active-brownout-all-paths.#{unique_test_class_hostname}:9081",
      },
    }, data)
  end

  def test_before_brownout_time
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "active-brownout-all-paths.#{unique_test_class_hostname}",
      fake_time: Time.now - 1000,
    )
  end

  def test_after_brownout_time
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "active-brownout-all-paths.#{unique_test_class_hostname}",
      fake_time: Time.now + 1000,
    )
  end

  def test_brownouts_do_not_apply_to_web_requests
    refute_in_brownout(
      "https://127.0.0.1:9081/",
      host: "active-brownout-all-paths.#{unique_test_class_hostname}",
    )
  end

  def test_schedule_boundary_times
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2024, 12, 31, 23, 59, 59),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 0, 0, 0),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 0, 0, 1),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 12, 0, 0),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 23, 59, 59),
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 2, 0, 0, 0),
    )

    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 6, 23, 59, 59),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 7, 0, 0, 0),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 7, 0, 0, 1),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 7, 12, 0, 0),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 7, 23, 59, 59),
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 8, 0, 0, 0),
    )
  end

  def test_path_regex_handling
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 0, 0, 0),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/foo",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 0, 0, 0),
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/utf8",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 0, 0, 0),
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "fixed-schedule-specific-regex.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 0, 0, 0),
    )
  end

  def test_custom_status_code_and_message
    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "custom-settings.#{unique_test_class_hostname}",
      expected_status_code: 403,
    )
    data = MultiJson.load(response.body)
    assert_equal({
      "error" => {
        "code" => "SCHEDULED_BROWNOUT",
        "message" => "Custom message",
      },
    }, data)
  end

  def test_matches_first_schedule_when_multiple_overlapping
    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 12, 0, 0),
    )
    data = MultiJson.load(response.body)
    assert_equal("Overlap message 1", data.fetch("error").fetch("message"))

    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 1, 12, 0, 0),
    )
    data = MultiJson.load(response.body)
    assert_equal("Overlap message 1", data.fetch("error").fetch("message"))

    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 2, 12, 0, 0),
    )
    data = MultiJson.load(response.body)
    assert_equal("Overlap message 2", data.fetch("error").fetch("message"))

    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 2, 12, 0, 0),
    )
    data = MultiJson.load(response.body)
    assert_equal("Overlap message 3", data.fetch("error").fetch("message"))

    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 3, 12, 0, 0),
    )
    data = MultiJson.load(response.body)
    assert_equal("Overlap message 2", data.fetch("error").fetch("message"))

    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 3, 12, 0, 0),
    )

    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 10, 12, 0, 0),
    )
    data = MultiJson.load(response.body)
    assert_equal("Overlap message 4", data.fetch("error").fetch("message"))

    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/headers/",
      host: "overlap.#{unique_test_class_hostname}",
      fake_time: Time.utc(2025, 1, 10, 12, 0, 0),
    )
  end

  def test_wildcard_host_handling
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard/info/",
      host: "dot-wildcard.#{unique_test_class_hostname}",
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard/info/",
      host: "foo.dot-wildcard.#{unique_test_class_hostname}",
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard/info/",
      host: "bar.dot-wildcard.#{unique_test_class_hostname}",
    )

    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard-root/info/",
      host: "dot-wildcard.#{unique_test_class_hostname}",
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard-root/info/",
      host: "foo.dot-wildcard.#{unique_test_class_hostname}",
      expected_status_code: 404,
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard-root/info/",
      host: "bar.dot-wildcard.#{unique_test_class_hostname}",
      expected_status_code: 404,
    )

    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard-explicit-subdomain/info/",
      host: "dot-wildcard.#{unique_test_class_hostname}",
      expected_status_code: 404,
    )
    assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard-explicit-subdomain/info/",
      host: "foo.dot-wildcard.#{unique_test_class_hostname}",
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/dot-wildcard-explicit-subdomain/info/",
      host: "bar.dot-wildcard.#{unique_test_class_hostname}",
      expected_status_code: 404,
    )

    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "foo.active-brownout-all-paths.#{unique_test_class_hostname}",
      expected_status_code: 404,
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "foo.active-brownout-all-paths.#{unique_test_class_hostname}",
      expected_status_code: 404,
    )
    refute_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "foo.active-brownout-all-paths.#{unique_test_class_hostname}",
      expected_status_code: 404,
    )
  end

  def test_logs_brownout_requests
    response = assert_in_brownout(
      "https://127.0.0.1:9081/#{unique_test_class_id}/info/",
      host: "active-brownout-all-paths.#{unique_test_class_hostname}",
    )
    record = wait_for_log(response)[:hit_source]
    assert_equal(410, record["response_status"])
    assert_logs_base_fields(record, api_user, request_host: "active-brownout-all-paths.#{unique_test_class_hostname}", request_scheme: "https")
    assert_equal("scheduled_brownout", record["gatekeeper_denied_code"])
  end

  private

  def assert_in_brownout(url, host:, fake_time: nil, expected_status_code: 410)
    response = Typhoeus.get(url, http_options.deep_merge({
      :headers => {
        "Host" => host,
        "X-Fake-Time" => fake_time&.strftime("%s.%L"),
      }.compact,
    }))
    assert_response_code(expected_status_code, response)

    data = MultiJson.load(response.body)
    assert_equal("SCHEDULED_BROWNOUT", data.fetch("error").fetch("code"))

    assert_equal("no-store", response.headers["Cache-Control"])

    response
  end

  def refute_in_brownout(url, host:, fake_time: nil, expected_status_code: 200)
    response = Typhoeus.get(url, http_options.deep_merge({
      :headers => {
        "Host" => host,
        "X-Fake-Time" => fake_time&.strftime("%s.%L"),
      }.compact,
    }))
    assert_response_code(expected_status_code, response)

    assert_nil(response.headers["Cache-Control"])

    response
  end
end

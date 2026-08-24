require_relative "../../../test_helper"

class Test::Apis::Admin::Stats::TestLogs < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
    LogItem.clean_indices!
  end

  def test_strips_api_keys_from_request_url_in_json
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_path => "/with_api_key/", :request_url_query => "foo=bar&api_key=my_secret_key", :request_query => { "foo" => "bar", "api_key" => "my_secret_key" }, :request_user_agent => unique_test_id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
      },
    }))

    assert_response_code(200, response)
    body = response.body
    data = MultiJson.load(body)
    assert_equal(1, data["recordsTotal"], data)
    assert_equal("/with_api_key/?foo=bar", data["data"][0]["request_url"])
    assert_equal("foo=bar", data["data"][0]["request_url_query"])
    if($config["opensearch"]["template_version"] < 2)
      assert_equal({ "foo" => "bar" }, data["data"][0]["request_query"])
    end
    refute_match("my_secret_key", body)
  end

  def test_strips_api_keys_from_request_url_in_csv
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_path => "/with_api_key/", :request_url_query => "api_key=my_secret_key&foo=bar", :request_query => { "foo" => "bar", "api_key" => "my_secret_key" }, :request_user_agent => unique_test_id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
      },
    }))

    assert_response_code(200, response)

    csv = CSV.parse(response.body)
    assert_includes(csv[1], "http://127.0.0.1/with_api_key/?foo=bar")
    refute_match("my_secret_key", response.body)
  end

  def test_downloading_csv_that_uses_scan_and_scroll_opensearch_query
    FactoryBot.create_list(:log_item, 1505, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_user_agent => unique_test_id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "search" => "",
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
      },
    }))

    assert_response_code(200, response)
    assert_equal("text/csv", response.headers["Content-Type"])
    assert_match("attachment; filename=\"api_logs_#{Time.now.utc.strftime("%Y-%m-%d")}.csv\"", response.headers["Content-Disposition"])

    csv = CSV.parse(response.body)
    assert_equal(1506, csv.length, csv)
    assert_equal([
      "Time",
      "Method",
      "Host",
      "URL",
      "User",
      "IP Address",
      "Country",
      "State",
      "City",
      "Status",
      "Reason Denied",
      "Response Time",
      "Content Type",
      "Accept Encoding",
      "User Agent",
      "User Agent Family",
      "User Agent Type",
      "Referer",
      "Origin",
      "Request Accept",
      "Request Connection",
      "Request Content Type",
      "Request Size",
      "Response Age",
      "Response Cache",
      "Response Cache Flags",
      "Response Content Encoding",
      "Response Content Length",
      "Response Server",
      "Response Size",
      "Response Transfer Encoding",
      "Response Custom Dimension 1",
      "Response Custom Dimension 2",
      "Response Custom Dimension 3",
      "User ID",
      "API Backend ID",
      "API Backend Resolved Host",
      "API Backend Response Code Details",
      "API Backend Response Flags",
      "Request ID",
    ], csv[0])
  end

  def test_query_builder_case_insensitive_defaults
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_user_agent => "MOZILLAAA-#{unique_test_id}")
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
        "query" => '{"condition":"AND","rules":[{"id":"request_user_agent","field":"request_user_agent","type":"string","input":"text","operator":"begins_with","value":"Mozilla"}]}',
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["recordsTotal"])
    assert_equal("MOZILLAAA-#{unique_test_id}", data["data"][0]["request_user_agent"])
  end

  def test_query_builder_api_key_case_sensitive
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :api_key => "AbCDeF", :request_user_agent => unique_test_id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
        "query" => '{"condition":"AND","rules":[{"id":"api_key","field":"api_key","type":"string","input":"text","operator":"begins_with","value":"AbCDeF"}]}',
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["recordsTotal"])
    assert_equal(unique_test_id, data["data"][0]["request_user_agent"])
  end

  def test_query_builder_nulls
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_user_agent => "#{unique_test_id}-null")
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :gatekeeper_denied_code => "api_key_missing", :request_user_agent => "#{unique_test_id}-not-null")
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
        "query" => '{"condition":"AND","rules":[{"id":"gatekeeper_denied_code","field":"gatekeeper_denied_code","type":"string","input":"select","operator":"is_not_null","value":null}]}',
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["recordsTotal"])
    assert_equal("#{unique_test_id}-not-null", data["data"][0]["request_user_agent"])
  end

  def test_query_builder_request_method
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_method => "POST", :request_user_agent => unique_test_id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
        "query" => '{"condition":"AND","rules":[{"id":"request_method","field":"request_method","type":"string","input":"select","operator":"equal","value":"post"}]}',
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["recordsTotal"])
    assert_equal("POST", data["data"][0]["request_method"])
    assert_equal(unique_test_id, data["data"][0]["request_user_agent"])
  end

  def test_no_results_non_existent_indices
    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2000-01-13",
        "end_at" => "2000-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "data" => [],
      "draw" => 0,
      "recordsFiltered" => 0,
      "recordsTotal" => 0,
    }, data)
  end

  def test_csv_timestamps_in_iso8601_utc_format
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_user_agent => unique_test_id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
      },
    }))

    assert_response_code(200, response)

    csv = CSV.parse(response.body)
    assert_equal(2, csv.length)
    assert_equal("Time", csv[0][0])
    assert_equal("2015-01-16T06:06:28.816Z", csv[1][0])
  end
end

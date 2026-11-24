require_relative "../../../test_helper"

class Test::Apis::V1::Analytics::TestDrilldown < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
    LogItem.clean_indices!
  end

  def test_level0_prefix
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create(:log_item, :request_host => "example.com", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(2, data["results"].length)
    assert_equal({
      "depth" => 0,
      "path" => "127.0.0.1/",
      "terminal" => false,
      "descendent_prefix" => "1/127.0.0.1/",
      "hits" => 2,
    }, data["results"][0])
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "0/127.0.0.1/", "label" => "127.0.0.1/", "type" => "number" },
      { "id" => "0/example.com/", "label" => "example.com/", "type" => "number" },
    ], data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 2, "f" => "2" },
      { "v" => 1, "f" => "1" },
    ] }, data["hits_over_time"]["rows"][1])
  end

  def test_level1_prefix
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create(:log_item, :request_host => "example.com", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "1/example.com/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["results"].length)
    assert_equal({
      "depth" => 1,
      "path" => "example.com/hello",
      "terminal" => true,
      "descendent_prefix" => "2/example.com/hello",
      "hits" => 1,
    }, data["results"][0])
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "1/example.com/hello", "label" => "example.com/hello", "type" => "number" },
    ], data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 1, "f" => "1" },
    ] }, data["hits_over_time"]["rows"][1])
  end

  def test_level2_prefix
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 2, :request_host => "example.com", :request_path => "/hello/foo", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create(:log_item, :request_host => "example.com", :request_path => "/hello/foo/bar", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "2/example.com/hello/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(2, data["results"].length)
    assert_equal({
      "depth" => 2,
      "path" => "example.com/hello/foo",
      "terminal" => true,
      "descendent_prefix" => "3/example.com/hello/foo",
      "hits" => 2,
    }, data["results"][0])
    assert_equal({
      "depth" => 2,
      "path" => "example.com/hello/foo/",
      "terminal" => false,
      "descendent_prefix" => "3/example.com/hello/foo/",
      "hits" => 1,
    }, data["results"][1])
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "2/example.com/hello/foo", "label" => "example.com/hello/foo", "type" => "number" },
      { "id" => "2/example.com/hello/foo/", "label" => "example.com/hello/foo/", "type" => "number" },
    ], data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 2, "f" => "2" },
      { "v" => 1, "f" => "1" },
    ] }, data["hits_over_time"]["rows"][1])
  end

  def test_prefix_not_contains
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    # Ensure that the second element in the array also contains "0/" to
    # ensure that the filtering and terms aggregations are both matching
    # based on prefix only.
    log = FactoryBot.create(:log_item, :request_host => "0", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    if($config["opensearch"]["template_version"] < 2)
      assert_equal(["0/0/", "1/0/hello"], log.serializable_hash.fetch("request_hierarchy"))
    end
    if($config["opensearch"]["template_version"] < 2)
      log = FactoryBot.create(:log_item, :request_hierarchy => ["foo/0/", "foo/0/hello"], :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
      assert_equal(["foo/0/", "foo/0/hello"], log.serializable_hash.fetch("request_hierarchy"))
    end
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(2, data["results"].length)
    assert_equal({
      "depth" => 0,
      "path" => "127.0.0.1/",
      "terminal" => false,
      "descendent_prefix" => "1/127.0.0.1/",
      "hits" => 2,
    }, data["results"][0])
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "0/127.0.0.1/", "label" => "127.0.0.1/", "type" => "number" },
      { "id" => "0/0/", "label" => "0/", "type" => "number" },
    ], data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 2, "f" => "2" },
      { "v" => 1, "f" => "1" },
    ] }, data["hits_over_time"]["rows"][1])
  end

  def test_prefix_regex_escaping
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create(:log_item, :request_host => "example.com", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    # Add other items in the request_hierarchy array that would match "0/."
    # (even though this isn't really a valid hierarchy definition). This
    # ensures that we also test whether the terms aggregations are being
    # escaped (and not just the overall filter).
    #
    # Note that in version 2 of the template, this matcher is based on
    # equality, rather than a prefix match, so there is some subtly different
    # behavior in version 2 (but in real practice, the app has always assumed
    # the values are equal).
    logs = FactoryBot.create_list(:log_item, 2, :request_host => ".", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    if($config["opensearch"]["template_version"] < 2)
      assert_equal(["0/./", "1/./hello"], logs[0].serializable_hash.fetch("request_hierarchy"))
    end
    log = FactoryBot.create(:log_item, :request_host => ".com", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    if($config["opensearch"]["template_version"] < 2)
      assert_equal(["0/.com/", "1/.com/hello"], log.serializable_hash.fetch("request_hierarchy"))
    end
    FactoryBot.create(:log_item, :request_host => "xcom", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create(:log_item, :request_host => "ycom", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/.",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    if($config["opensearch"]["template_version"] < 2)
      assert_equal(2, data["results"].length)
    else
      assert_equal(1, data["results"].length)
    end
    assert_equal({
      "depth" => 0,
      "path" => "./",
      "terminal" => false,
      "descendent_prefix" => "1/./",
      "hits" => 2,
    }, data["results"][0])
    if($config["opensearch"]["template_version"] < 2)
      assert_equal({
        "depth" => 0,
        "path" => ".com/",
        "terminal" => false,
        "descendent_prefix" => "1/.com/",
        "hits" => 1,
      }, data["results"][1])
    end
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "0/./", "label" => "./", "type" => "number" },
      $config["opensearch"]["template_version"] < 2 ? { "id" => "0/.com/", "label" => ".com/", "type" => "number" } : nil,
    ].compact, data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 2, "f" => "2" },
      $config["opensearch"]["template_version"] < 2 ? { "v" => 1, "f" => "1" } : nil,
    ].compact }, data["hits_over_time"]["rows"][1])

    # Check for a more proper "1/." prefix (the correct depth to have a
    # trailing host).
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "1/.",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    if($config["opensearch"]["template_version"] < 2)
      assert_equal(2, data["results"].length)
    else
      assert_equal(1, data["results"].length)
    end
    assert_equal({
      "depth" => 1,
      "path" => "./hello",
      "terminal" => true,
      "descendent_prefix" => "2/./hello",
      "hits" => 2,
    }, data["results"][0])
    if($config["opensearch"]["template_version"] < 2)
      assert_equal({
        "depth" => 1,
        "path" => ".com/hello",
        "terminal" => true,
        "descendent_prefix" => "2/.com/hello",
        "hits" => 1,
      }, data["results"][1])
    end
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "1/./hello", "label" => "./hello", "type" => "number" },
      $config["opensearch"]["template_version"] < 2 ? { "id" => "1/.com/hello", "label" => ".com/hello", "type" => "number" } : nil,
    ].compact, data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 2, "f" => "2" },
      $config["opensearch"]["template_version"] < 2 ? { "v" => 1, "f" => "1" } : nil,
    ].compact }, data["hits_over_time"]["rows"][1])

    # Check for a more proper "1/./" prefix (the correct depth to have a
    # trailing host, and with the expected trailing slash).
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "1/./",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["results"].length)
    assert_equal({
      "depth" => 1,
      "path" => "./hello",
      "terminal" => true,
      "descendent_prefix" => "2/./hello",
      "hits" => 2,
    }, data["results"][0])
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "1/./hello", "label" => "./hello", "type" => "number" },
    ].compact, data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 2, "f" => "2" },
    ].compact }, data["hits_over_time"]["rows"][1])
  end

  def test_all_results_top_10_for_chart
    FactoryBot.create_list(:log_item, 2, :request_host => "127.0.0.1", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 2, :request_host => "127.0.0.2", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 3, :request_host => "127.0.0.3", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 10, :request_host => "127.0.0.4", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 11, :request_host => "127.0.0.5", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 12, :request_host => "127.0.0.6", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 13, :request_host => "127.0.0.7", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 14, :request_host => "127.0.0.8", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 15, :request_host => "127.0.0.9", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 16, :request_host => "127.0.0.10", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 17, :request_host => "127.0.0.11", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 18, :request_host => "127.0.0.12", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create_list(:log_item, 1, :request_host => "127.0.0.13", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(13, data["results"].length)
    assert_equal({
      "depth" => 0,
      "path" => "127.0.0.12/",
      "terminal" => false,
      "descendent_prefix" => "1/127.0.0.12/",
      "hits" => 18,
    }, data["results"][0])
    assert_equal({
      "depth" => 0,
      "path" => "127.0.0.13/",
      "terminal" => false,
      "descendent_prefix" => "1/127.0.0.13/",
      "hits" => 1,
    }, data["results"][12])
    assert_equal([
      { "id" => "date", "label" => "Date", "type" => "datetime" },
      { "id" => "0/127.0.0.12/", "label" => "127.0.0.12/", "type" => "number" },
      { "id" => "0/127.0.0.11/", "label" => "127.0.0.11/", "type" => "number" },
      { "id" => "0/127.0.0.10/", "label" => "127.0.0.10/", "type" => "number" },
      { "id" => "0/127.0.0.9/", "label" => "127.0.0.9/", "type" => "number" },
      { "id" => "0/127.0.0.8/", "label" => "127.0.0.8/", "type" => "number" },
      { "id" => "0/127.0.0.7/", "label" => "127.0.0.7/", "type" => "number" },
      { "id" => "0/127.0.0.6/", "label" => "127.0.0.6/", "type" => "number" },
      { "id" => "0/127.0.0.5/", "label" => "127.0.0.5/", "type" => "number" },
      { "id" => "0/127.0.0.4/", "label" => "127.0.0.4/", "type" => "number" },
      { "id" => "0/127.0.0.3/", "label" => "127.0.0.3/", "type" => "number" },
      { "id" => "other", "label" => "Other", "type" => "number" },
    ], data["hits_over_time"]["cols"])
    assert_equal(6, data["hits_over_time"]["rows"].length)
    assert_equal({ "c" => [
      { "v" => 1421218800000, "f" => "Wed, Jan 14, 2015" },
      { "v" => 18, "f" => "18" },
      { "v" => 17, "f" => "17" },
      { "v" => 16, "f" => "16" },
      { "v" => 15, "f" => "15" },
      { "v" => 14, "f" => "14" },
      { "v" => 13, "f" => "13" },
      { "v" => 12, "f" => "12" },
      { "v" => 11, "f" => "11" },
      { "v" => 10, "f" => "10" },
      { "v" => 3, "f" => "3" },
      { "v" => 5, "f" => "5" },
    ] }, data["hits_over_time"]["rows"][1])
  end

  def test_hits_over_time_max_buckets
    13.times do |i|
      FactoryBot.create(:log_item, :request_host => "127.0.0.#{i + 1}", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    end
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
        :hits_over_time_max_buckets => 13,
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(13, data["results"].length)

    # With hits_over_time_max_buckets=13, all 13 hosts should appear in the
    # chart columns (date + 13 hosts = 14 columns, no "Other" column).
    assert_equal(14, data["hits_over_time"]["cols"].length)
    assert_equal({ "id" => "date", "label" => "Date", "type" => "datetime" }, data["hits_over_time"]["cols"][0])

    # Verify the data row has 14 cells (date + 13 hosts, no "Other").
    assert_equal(14, data["hits_over_time"]["rows"][1]["c"].length)
  end

  def test_hits_over_time_max_buckets_out_of_range
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    LogItem.refresh_indices!

    # Value over 100 should return a validation error.
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
        :hits_over_time_max_buckets => 101,
      },
    }))

    assert_response_code(422, response)

    # Value of 0 should return a validation error.
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
        :hits_over_time_max_buckets => 0,
      },
    }))

    assert_response_code(422, response)
  end

  def test_hits_over_time_max_buckets_defaults_to_10
    13.times do |i|
      FactoryBot.create(:log_item, :request_host => "127.0.0.#{i + 1}", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    end
    LogItem.refresh_indices!

    # Without hits_over_time_max_buckets, the chart should default to top 10
    # (date + 10 hosts + "Other" = 12 columns).
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(13, data["results"].length)
    assert_equal(12, data["hits_over_time"]["cols"].length)
    assert_equal({ "id" => "other", "label" => "Other", "type" => "number" }, data["hits_over_time"]["cols"][11])
  end

  def test_time_zone
    Time.use_zone("America/Denver") do
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-01-12T23:59:59"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-01-13T00:00:00"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-01-18T23:59:59"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-01-19T00:00:00"))
    end
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_operator(data["results"].length, :>, 0)
    assert_equal(2, data["results"][0]["hits"])
    assert_equal("Tue, Jan 13, 2015", data["hits_over_time"]["rows"][0]["c"][0]["f"])
    assert_equal(1421132400000, data["hits_over_time"]["rows"][0]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][0]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][0]["c"][1]["v"])
    assert_equal("Sun, Jan 18, 2015", data["hits_over_time"]["rows"][5]["c"][0]["f"])
    assert_equal(1421564400000, data["hits_over_time"]["rows"][5]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][5]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][5]["c"][1]["v"])
  end

  def test_bins_daily_results_daylight_saving_time_begin
    Time.use_zone("UTC") do
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-03-08T00:00:00"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-03-08T08:59:59"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-03-08T09:00:00"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-03-09T10:00:00"))
    end
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-03-07",
        :end_at => "2015-03-09",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_operator(data["results"].length, :>, 0)
    assert_equal(4, data["results"][0]["hits"])
    assert_equal("Sat, Mar 7, 2015", data["hits_over_time"]["rows"][0]["c"][0]["f"])
    assert_equal(1425711600000, data["hits_over_time"]["rows"][0]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][0]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][0]["c"][1]["v"])
    assert_equal("Sun, Mar 8, 2015", data["hits_over_time"]["rows"][1]["c"][0]["f"])
    assert_equal(1425798000000, data["hits_over_time"]["rows"][1]["c"][0]["v"])
    assert_equal("2", data["hits_over_time"]["rows"][1]["c"][1]["f"])
    assert_equal(2, data["hits_over_time"]["rows"][1]["c"][1]["v"])
    assert_equal("Mon, Mar 9, 2015", data["hits_over_time"]["rows"][2]["c"][0]["f"])
    assert_equal(1425880800000, data["hits_over_time"]["rows"][2]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][2]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][2]["c"][1]["v"])
  end

  def test_bins_hourly_results_daylight_saving_time_begin
    Time.use_zone("UTC") do
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-03-08T08:59:59"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2015-03-08T09:00:00"))
    end
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-03-08",
        :end_at => "2015-03-08",
        :interval => "hour",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_operator(data["results"].length, :>, 0)
    assert_equal(2, data["results"][0]["hits"])
    assert_equal("Sun, Mar 8, 2015 12:00AM MST", data["hits_over_time"]["rows"][0]["c"][0]["f"])
    assert_equal(1425798000000, data["hits_over_time"]["rows"][0]["c"][0]["v"])
    assert_equal("0", data["hits_over_time"]["rows"][0]["c"][1]["f"])
    assert_equal(0, data["hits_over_time"]["rows"][0]["c"][1]["v"])
    assert_equal("Sun, Mar 8, 2015 1:00AM MST", data["hits_over_time"]["rows"][1]["c"][0]["f"])
    assert_equal(1425801600000, data["hits_over_time"]["rows"][1]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][1]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][1]["c"][1]["v"])
    assert_equal("Sun, Mar 8, 2015 3:00AM MDT", data["hits_over_time"]["rows"][2]["c"][0]["f"])
    assert_equal(1425805200000, data["hits_over_time"]["rows"][2]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][2]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][2]["c"][1]["v"])
    assert_equal("Sun, Mar 8, 2015 4:00AM MDT", data["hits_over_time"]["rows"][3]["c"][0]["f"])
    assert_equal(1425808800000, data["hits_over_time"]["rows"][3]["c"][0]["v"])
    assert_equal("0", data["hits_over_time"]["rows"][3]["c"][1]["f"])
    assert_equal(0, data["hits_over_time"]["rows"][3]["c"][1]["v"])
  end

  def test_bins_daily_results_daylight_saving_time_end
    Time.use_zone("UTC") do
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2014-11-02T00:00:00"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2014-11-02T08:59:59"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2014-11-02T09:00:00"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2014-11-03T10:00:00"))
    end
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2014-11-01",
        :end_at => "2014-11-03",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_operator(data["results"].length, :>, 0)
    assert_equal(4, data["results"][0]["hits"])
    assert_equal("Sat, Nov 1, 2014", data["hits_over_time"]["rows"][0]["c"][0]["f"])
    assert_equal(1414821600000, data["hits_over_time"]["rows"][0]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][0]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][0]["c"][1]["v"])
    assert_equal("Sun, Nov 2, 2014", data["hits_over_time"]["rows"][1]["c"][0]["f"])
    assert_equal(1414908000000, data["hits_over_time"]["rows"][1]["c"][0]["v"])
    assert_equal("2", data["hits_over_time"]["rows"][1]["c"][1]["f"])
    assert_equal(2, data["hits_over_time"]["rows"][1]["c"][1]["v"])
    assert_equal("Mon, Nov 3, 2014", data["hits_over_time"]["rows"][2]["c"][0]["f"])
    assert_equal(1414998000000, data["hits_over_time"]["rows"][2]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][2]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][2]["c"][1]["v"])
  end

  def test_bins_hourly_results_daylight_saving_time_end
    Time.use_zone("UTC") do
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2014-11-02T08:59:59"))
      FactoryBot.create(:log_item, :request_at => Time.zone.parse("2014-11-02T09:00:00"))
    end
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2014-11-02",
        :end_at => "2014-11-02",
        :interval => "hour",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_operator(data["results"].length, :>, 0)
    assert_equal(2, data["results"][0]["hits"])
    assert_equal("Sun, Nov 2, 2014 1:00AM MDT", data["hits_over_time"]["rows"][1]["c"][0]["f"])
    assert_equal(1414911600000, data["hits_over_time"]["rows"][1]["c"][0]["v"])
    assert_equal("0", data["hits_over_time"]["rows"][1]["c"][1]["f"])
    assert_equal(0, data["hits_over_time"]["rows"][1]["c"][1]["v"])
    assert_equal("Sun, Nov 2, 2014 1:00AM MST", data["hits_over_time"]["rows"][2]["c"][0]["f"])
    assert_equal(1414915200000, data["hits_over_time"]["rows"][2]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][2]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][2]["c"][1]["v"])
    assert_equal("Sun, Nov 2, 2014 2:00AM MST", data["hits_over_time"]["rows"][3]["c"][0]["f"])
    assert_equal(1414918800000, data["hits_over_time"]["rows"][3]["c"][0]["v"])
    assert_equal("1", data["hits_over_time"]["rows"][3]["c"][1]["f"])
    assert_equal(1, data["hits_over_time"]["rows"][3]["c"][1]["v"])
    assert_equal("Sun, Nov 2, 2014 3:00AM MST", data["hits_over_time"]["rows"][4]["c"][0]["f"])
    assert_equal(1414922400000, data["hits_over_time"]["rows"][4]["c"][0]["v"])
    assert_equal("0", data["hits_over_time"]["rows"][4]["c"][1]["f"])
    assert_equal(0, data["hits_over_time"]["rows"][4]["c"][1]["v"])
  end

  def test_csv_download
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    FactoryBot.create(:log_item, :request_host => "example.com", :request_path => "/hello/foo", :request_at => Time.parse("2015-01-15T00:00:00Z").utc)
    LogItem.refresh_indices!

    # Level 0 filter
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    assert_equal("text/csv", response.headers["Content-Type"])
    assert_match("attachment; filename=\"api_drilldown_#{Time.now.utc.strftime("%Y-%m-%d")}.csv\"", response.headers["Content-Disposition"])

    csv = CSV.parse(response.body)
    assert_equal(3, csv.length, csv)
    assert_equal(["Path", "Hits"], csv[0])
    assert_equal(["127.0.0.1/", "2"], csv[1])
    assert_equal(["example.com/", "1"], csv[2])

    # Level 1 filter
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "1/example.com/",
      },
    }))

    assert_response_code(200, response)
    assert_equal("text/csv", response.headers["Content-Type"])
    assert_match("attachment; filename=\"api_drilldown_#{Time.now.utc.strftime("%Y-%m-%d")}.csv\"", response.headers["Content-Disposition"])

    csv = CSV.parse(response.body)
    assert_equal(2, csv.length, csv)
    assert_equal(["Path", "Hits"], csv[0])
    assert_equal(["example.com/hello/", "1"], csv[1])

    # Level 2 filter
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        :search => "",
        :start_at => "2015-01-13",
        :end_at => "2015-01-18",
        :interval => "day",
        :prefix => "2/example.com/hello/",
      },
    }))

    assert_response_code(200, response)
    assert_equal("text/csv", response.headers["Content-Type"])
    assert_match("attachment; filename=\"api_drilldown_#{Time.now.utc.strftime("%Y-%m-%d")}.csv\"", response.headers["Content-Disposition"])

    csv = CSV.parse(response.body)
    assert_equal(2, csv.length, csv)
    assert_equal(["Path", "Hits"], csv[0])
    assert_equal(["example.com/hello/foo", "1"], csv[1])
  end

  def test_no_results_non_existent_indices
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/analytics/drilldown.json", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => "",
        :start_at => "2000-01-13",
        :end_at => "2000-01-18",
        :interval => "day",
        :prefix => "0/",
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "breadcrumbs" => [
        {
          "crumb" => "All Hosts",
          "prefix" => "0/",
        },
      ],
      "hits_over_time" => {
        "cols" => [
          {
            "id" => "date",
            "label" => "Date",
            "type" => "datetime",
          },
        ],
        "rows" => [
          {
            "c" => [
              { "f" => "Thu, Jan 13, 2000", "v" => 947746800000 },
            ],
          },
          {
            "c" => [
              { "f" => "Fri, Jan 14, 2000", "v" => 947833200000 },
            ],
          },
          {
            "c" => [
              { "f" => "Sat, Jan 15, 2000", "v" => 947919600000 },
            ],
          },
          {
            "c" => [
              { "f" => "Sun, Jan 16, 2000", "v" => 948006000000 },
            ],
          },
          {
            "c" => [
              { "f" => "Mon, Jan 17, 2000", "v" => 948092400000 },
            ],
          },
          {
            "c" => [
              { "f" => "Tue, Jan 18, 2000", "v" => 948178800000 },
            ],
          },
        ],
      },
      "results" => [],
    }, data)
  end
end

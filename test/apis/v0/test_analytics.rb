require_relative "../../test_helper"

class Test::Apis::V0::TestAnalytics < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
    LogItem.clean_indices!

    Time.use_zone($config["analytics"]["timezone"]) do
      @start_time = Time.zone.parse($config["web"]["analytics_v0_summary_start_time"])
      @end_time = Time.zone.parse($config["web"]["analytics_v0_summary_end_time"])
    end

    FactoryBot.create_list(:log_item, 1, :request_at => @start_time)
    LogItem.refresh_indices!
  end

  def test_forbids_api_key_without_any_role
    user = FactoryBot.create(:api_user)
    response = make_request(user)
    assert_response_code(401, response)
  end

  def test_forbids_api_key_without_correct_role
    user = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-public-metricsx"],
    })

    response = make_request(user)
    assert_response_code(401, response)
  end

  def test_allows_api_key_with_role
    response = make_request
    assert_response_code(200, response)
  end

  def test_allows_api_key_without_role_if_configured
    user = FactoryBot.create(:api_user)
    response = make_request(user)
    assert_response_code(401, response)

    override_config({
      "web" => {
        "analytics_v0_summary_required_role" => nil,
      },
    }) do
      response = make_request(user)
      assert_response_code(200, response)
    end
  end

  def test_expected_response
    LogItem.clean_indices!

    backend1 = FactoryBot.create(:api_backend, :frontend_host => "localhost1")
    backend2 = FactoryBot.create(:api_backend, :frontend_host => "localhost2")
    backend3 = FactoryBot.create(:api_backend, :organization_name => "Another Org", :frontend_host => "localhost3")
    backend4 = FactoryBot.create(:api_backend, :status_description => nil, :frontend_host => "localhost4")
    FactoryBot.create(:api_backend, :organization_name => "Org without data", :frontend_host => "localhost5")

    users = FactoryBot.create_list(:api_user, 3, :created_at => @start_time)
    FactoryBot.create_list(:log_item, 1, :request_at => @start_time, :response_time => 100, :request_host => backend1.frontend_host, :request_path => backend1.url_matches[0].frontend_prefix)
    FactoryBot.create_list(:log_item, 1, :request_at => @start_time, :response_time => 100, :request_host => backend2.frontend_host, :request_path => backend2.url_matches[0].frontend_prefix)
    FactoryBot.create_list(:log_item, 1, :request_at => @start_time, :response_time => 100, :request_host => backend3.frontend_host, :request_path => backend3.url_matches[0].frontend_prefix)
    FactoryBot.create_list(:log_item, 1, :request_at => @start_time, :response_time => 100, :request_host => backend4.frontend_host, :request_path => backend4.url_matches[0].frontend_prefix)
    FactoryBot.create_list(:log_item, 1, :request_at => @end_time, :response_time => 200, :request_host => backend1.frontend_host, :request_path => backend1.url_matches[0].frontend_prefix)
    FactoryBot.create_list(:log_item, 1, :request_at => @end_time, :response_time => 100, :request_host => backend3.frontend_host, :request_path => backend3.url_matches[0].frontend_prefix, :user_id => users.first.id)
    FactoryBot.create_list(:log_item, 2, :request_at => @end_time, :response_time => 1000, :request_host => backend3.frontend_host, :request_path => backend3.url_matches[0].frontend_prefix, :user_id => users.last.id)
    LogItem.refresh_indices!

    response = make_request
    assert_response_code(200, response)
    assert_equal("MISS", response.headers["X-Cache"])

    data = MultiJson.load(response.body)
    assert_equal([
      "cached_at",
      "end_time",
      "production_apis",
      "start_time",
      "timezone",
    ].sort, data.keys.sort)
    assert_match_iso8601(data.fetch("cached_at"))
    assert_match_iso8601(data.fetch("end_time"))
    assert_kind_of(Hash, data.fetch("production_apis"))
    assert_match_iso8601(data.fetch("start_time"))
    assert_equal("2013-06-01T06:00:00Z", data.fetch("start_time"))
    assert_equal("America/Denver", data.fetch("timezone"))

    assert_equal({
      "organizations" => [
        {
          "active_api_keys" => {
            "monthly" => [
              ["2013-06", 1],
              ["2013-07", 0],
              ["2013-08", 2],
            ],
            "recent" => {
              "total" => 2,
              "daily" => [
                ["2013-08-02", 0],
                ["2013-08-03", 0],
                ["2013-08-04", 0],
                ["2013-08-05", 0],
                ["2013-08-06", 0],
                ["2013-08-07", 0],
                ["2013-08-08", 0],
                ["2013-08-09", 0],
                ["2013-08-10", 0],
                ["2013-08-11", 0],
                ["2013-08-12", 0],
                ["2013-08-13", 0],
                ["2013-08-14", 0],
                ["2013-08-15", 0],
                ["2013-08-16", 0],
                ["2013-08-17", 0],
                ["2013-08-18", 0],
                ["2013-08-19", 0],
                ["2013-08-20", 0],
                ["2013-08-21", 0],
                ["2013-08-22", 0],
                ["2013-08-23", 0],
                ["2013-08-24", 0],
                ["2013-08-25", 0],
                ["2013-08-26", 0],
                ["2013-08-27", 0],
                ["2013-08-28", 0],
                ["2013-08-29", 0],
                ["2013-08-30", 0],
                ["2013-08-31", 2],
              ],
            },
            "total" => 3,
          },
          "average_response_times" => {
            "average" => 550,
            "monthly" => [
              ["2013-06", 100],
              ["2013-07", nil],
              ["2013-08", 700],
            ],
            "recent" => {
              "average" => 700,
              "daily" => [
                ["2013-08-02", nil],
                ["2013-08-03", nil],
                ["2013-08-04", nil],
                ["2013-08-05", nil],
                ["2013-08-06", nil],
                ["2013-08-07", nil],
                ["2013-08-08", nil],
                ["2013-08-09", nil],
                ["2013-08-10", nil],
                ["2013-08-11", nil],
                ["2013-08-12", nil],
                ["2013-08-13", nil],
                ["2013-08-14", nil],
                ["2013-08-15", nil],
                ["2013-08-16", nil],
                ["2013-08-17", nil],
                ["2013-08-18", nil],
                ["2013-08-19", nil],
                ["2013-08-20", nil],
                ["2013-08-21", nil],
                ["2013-08-22", nil],
                ["2013-08-23", nil],
                ["2013-08-24", nil],
                ["2013-08-25", nil],
                ["2013-08-26", nil],
                ["2013-08-27", nil],
                ["2013-08-28", nil],
                ["2013-08-29", nil],
                ["2013-08-30", nil],
                ["2013-08-31", 700],
              ],
            },
          },
          "api_backend_url_match_count" => 1,
          "name" => "Another Org",
          "api_backend_count" => 1,
          "hits" => {
            "monthly" => [
              ["2013-06", 1],
              ["2013-07", 0],
              ["2013-08", 3],
            ],
            "recent" => {
              "total" => 3,
              "daily" => [
                ["2013-08-02", 0],
                ["2013-08-03", 0],
                ["2013-08-04", 0],
                ["2013-08-05", 0],
                ["2013-08-06", 0],
                ["2013-08-07", 0],
                ["2013-08-08", 0],
                ["2013-08-09", 0],
                ["2013-08-10", 0],
                ["2013-08-11", 0],
                ["2013-08-12", 0],
                ["2013-08-13", 0],
                ["2013-08-14", 0],
                ["2013-08-15", 0],
                ["2013-08-16", 0],
                ["2013-08-17", 0],
                ["2013-08-18", 0],
                ["2013-08-19", 0],
                ["2013-08-20", 0],
                ["2013-08-21", 0],
                ["2013-08-22", 0],
                ["2013-08-23", 0],
                ["2013-08-24", 0],
                ["2013-08-25", 0],
                ["2013-08-26", 0],
                ["2013-08-27", 0],
                ["2013-08-28", 0],
                ["2013-08-29", 0],
                ["2013-08-30", 0],
                ["2013-08-31", 3],
              ],
            },
            "total" => 4,
          },
        },
        {
          "active_api_keys" => {
            "monthly" => [
              ["2013-06", 1],
              ["2013-07", 0],
              ["2013-08", 1],
            ],
            "recent" => {
              "total" => 1,
              "daily" => [
                ["2013-08-02", 0],
                ["2013-08-03", 0],
                ["2013-08-04", 0],
                ["2013-08-05", 0],
                ["2013-08-06", 0],
                ["2013-08-07", 0],
                ["2013-08-08", 0],
                ["2013-08-09", 0],
                ["2013-08-10", 0],
                ["2013-08-11", 0],
                ["2013-08-12", 0],
                ["2013-08-13", 0],
                ["2013-08-14", 0],
                ["2013-08-15", 0],
                ["2013-08-16", 0],
                ["2013-08-17", 0],
                ["2013-08-18", 0],
                ["2013-08-19", 0],
                ["2013-08-20", 0],
                ["2013-08-21", 0],
                ["2013-08-22", 0],
                ["2013-08-23", 0],
                ["2013-08-24", 0],
                ["2013-08-25", 0],
                ["2013-08-26", 0],
                ["2013-08-27", 0],
                ["2013-08-28", 0],
                ["2013-08-29", 0],
                ["2013-08-30", 0],
                ["2013-08-31", 1],
              ],
            },
            "total" => 1,
          },
          "average_response_times" => {
            "average" => 133,
            "monthly" => [
              ["2013-06", 100],
              ["2013-07", nil],
              ["2013-08", 200],
            ],
            "recent" => {
              "average" => 200,
              "daily" => [
                ["2013-08-02", nil],
                ["2013-08-03", nil],
                ["2013-08-04", nil],
                ["2013-08-05", nil],
                ["2013-08-06", nil],
                ["2013-08-07", nil],
                ["2013-08-08", nil],
                ["2013-08-09", nil],
                ["2013-08-10", nil],
                ["2013-08-11", nil],
                ["2013-08-12", nil],
                ["2013-08-13", nil],
                ["2013-08-14", nil],
                ["2013-08-15", nil],
                ["2013-08-16", nil],
                ["2013-08-17", nil],
                ["2013-08-18", nil],
                ["2013-08-19", nil],
                ["2013-08-20", nil],
                ["2013-08-21", nil],
                ["2013-08-22", nil],
                ["2013-08-23", nil],
                ["2013-08-24", nil],
                ["2013-08-25", nil],
                ["2013-08-26", nil],
                ["2013-08-27", nil],
                ["2013-08-28", nil],
                ["2013-08-29", nil],
                ["2013-08-30", nil],
                ["2013-08-31", 200],
              ],
            },
          },
          "api_backend_url_match_count" => 2,
          "name" => "Example Org",
          "api_backend_count" => 2,
          "hits" => {
            "monthly" => [
              ["2013-06", 2],
              ["2013-07", 0],
              ["2013-08", 1],
            ],
            "recent" => {
              "total" => 1,
              "daily" => [
                ["2013-08-02", 0],
                ["2013-08-03", 0],
                ["2013-08-04", 0],
                ["2013-08-05", 0],
                ["2013-08-06", 0],
                ["2013-08-07", 0],
                ["2013-08-08", 0],
                ["2013-08-09", 0],
                ["2013-08-10", 0],
                ["2013-08-11", 0],
                ["2013-08-12", 0],
                ["2013-08-13", 0],
                ["2013-08-14", 0],
                ["2013-08-15", 0],
                ["2013-08-16", 0],
                ["2013-08-17", 0],
                ["2013-08-18", 0],
                ["2013-08-19", 0],
                ["2013-08-20", 0],
                ["2013-08-21", 0],
                ["2013-08-22", 0],
                ["2013-08-23", 0],
                ["2013-08-24", 0],
                ["2013-08-25", 0],
                ["2013-08-26", 0],
                ["2013-08-27", 0],
                ["2013-08-28", 0],
                ["2013-08-29", 0],
                ["2013-08-30", 0],
                ["2013-08-31", 1],
              ],
            },
            "total" => 3,
          },
        },
        {
          "active_api_keys" => {
            "monthly" => [
              ["2013-06", 0],
              ["2013-07", 0],
              ["2013-08", 0],
            ],
            "recent" => {
              "total" => 0,
              "daily" => [
                ["2013-08-02", 0],
                ["2013-08-03", 0],
                ["2013-08-04", 0],
                ["2013-08-05", 0],
                ["2013-08-06", 0],
                ["2013-08-07", 0],
                ["2013-08-08", 0],
                ["2013-08-09", 0],
                ["2013-08-10", 0],
                ["2013-08-11", 0],
                ["2013-08-12", 0],
                ["2013-08-13", 0],
                ["2013-08-14", 0],
                ["2013-08-15", 0],
                ["2013-08-16", 0],
                ["2013-08-17", 0],
                ["2013-08-18", 0],
                ["2013-08-19", 0],
                ["2013-08-20", 0],
                ["2013-08-21", 0],
                ["2013-08-22", 0],
                ["2013-08-23", 0],
                ["2013-08-24", 0],
                ["2013-08-25", 0],
                ["2013-08-26", 0],
                ["2013-08-27", 0],
                ["2013-08-28", 0],
                ["2013-08-29", 0],
                ["2013-08-30", 0],
                ["2013-08-31", 0],
              ],
            },
            "total" => 0,
          },
          "average_response_times" => {
            "average" => nil,
            "monthly" => [
              ["2013-06", nil],
              ["2013-07", nil],
              ["2013-08", nil],
            ],
            "recent" => {
              "average" => nil,
              "daily" => [
                ["2013-08-02", nil],
                ["2013-08-03", nil],
                ["2013-08-04", nil],
                ["2013-08-05", nil],
                ["2013-08-06", nil],
                ["2013-08-07", nil],
                ["2013-08-08", nil],
                ["2013-08-09", nil],
                ["2013-08-10", nil],
                ["2013-08-11", nil],
                ["2013-08-12", nil],
                ["2013-08-13", nil],
                ["2013-08-14", nil],
                ["2013-08-15", nil],
                ["2013-08-16", nil],
                ["2013-08-17", nil],
                ["2013-08-18", nil],
                ["2013-08-19", nil],
                ["2013-08-20", nil],
                ["2013-08-21", nil],
                ["2013-08-22", nil],
                ["2013-08-23", nil],
                ["2013-08-24", nil],
                ["2013-08-25", nil],
                ["2013-08-26", nil],
                ["2013-08-27", nil],
                ["2013-08-28", nil],
                ["2013-08-29", nil],
                ["2013-08-30", nil],
                ["2013-08-31", nil],
              ],
            },
          },
          "api_backend_url_match_count" => 1,
          "name" => "Org without data",
          "api_backend_count" => 1,
          "hits" => {
            "monthly" => [
              ["2013-06", 0],
              ["2013-07", 0],
              ["2013-08", 0],
            ],
            "recent" => {
              "total" => 0,
              "daily" => [
                ["2013-08-02", 0],
                ["2013-08-03", 0],
                ["2013-08-04", 0],
                ["2013-08-05", 0],
                ["2013-08-06", 0],
                ["2013-08-07", 0],
                ["2013-08-08", 0],
                ["2013-08-09", 0],
                ["2013-08-10", 0],
                ["2013-08-11", 0],
                ["2013-08-12", 0],
                ["2013-08-13", 0],
                ["2013-08-14", 0],
                ["2013-08-15", 0],
                ["2013-08-16", 0],
                ["2013-08-17", 0],
                ["2013-08-18", 0],
                ["2013-08-19", 0],
                ["2013-08-20", 0],
                ["2013-08-21", 0],
                ["2013-08-22", 0],
                ["2013-08-23", 0],
                ["2013-08-24", 0],
                ["2013-08-25", 0],
                ["2013-08-26", 0],
                ["2013-08-27", 0],
                ["2013-08-28", 0],
                ["2013-08-29", 0],
                ["2013-08-30", 0],
                ["2013-08-31", 0],
              ],
            },
            "total" => 0,
          },
        },
      ],
      "all" => {
        "active_api_keys" => {
          "monthly" => [
            ["2013-06", 1],
            ["2013-07", 0],
            ["2013-08", 3],
          ],
          "recent" => {
            "total" => 3,
            "daily" => [
              ["2013-08-02", 0],
              ["2013-08-03", 0],
              ["2013-08-04", 0],
              ["2013-08-05", 0],
              ["2013-08-06", 0],
              ["2013-08-07", 0],
              ["2013-08-08", 0],
              ["2013-08-09", 0],
              ["2013-08-10", 0],
              ["2013-08-11", 0],
              ["2013-08-12", 0],
              ["2013-08-13", 0],
              ["2013-08-14", 0],
              ["2013-08-15", 0],
              ["2013-08-16", 0],
              ["2013-08-17", 0],
              ["2013-08-18", 0],
              ["2013-08-19", 0],
              ["2013-08-20", 0],
              ["2013-08-21", 0],
              ["2013-08-22", 0],
              ["2013-08-23", 0],
              ["2013-08-24", 0],
              ["2013-08-25", 0],
              ["2013-08-26", 0],
              ["2013-08-27", 0],
              ["2013-08-28", 0],
              ["2013-08-29", 0],
              ["2013-08-30", 0],
              ["2013-08-31", 3],
            ],
          },
          "total" => 3,
        },
        "average_response_times" => {
          "average" => 371,
          "monthly" => [
            ["2013-06", 100],
            ["2013-07", nil],
            ["2013-08", 575],
          ],
          "recent" => {
            "average" => 575,
            "daily" => [
              ["2013-08-02", nil],
              ["2013-08-03", nil],
              ["2013-08-04", nil],
              ["2013-08-05", nil],
              ["2013-08-06", nil],
              ["2013-08-07", nil],
              ["2013-08-08", nil],
              ["2013-08-09", nil],
              ["2013-08-10", nil],
              ["2013-08-11", nil],
              ["2013-08-12", nil],
              ["2013-08-13", nil],
              ["2013-08-14", nil],
              ["2013-08-15", nil],
              ["2013-08-16", nil],
              ["2013-08-17", nil],
              ["2013-08-18", nil],
              ["2013-08-19", nil],
              ["2013-08-20", nil],
              ["2013-08-21", nil],
              ["2013-08-22", nil],
              ["2013-08-23", nil],
              ["2013-08-24", nil],
              ["2013-08-25", nil],
              ["2013-08-26", nil],
              ["2013-08-27", nil],
              ["2013-08-28", nil],
              ["2013-08-29", nil],
              ["2013-08-30", nil],
              ["2013-08-31", 575],
            ],
          },
        },
        "hits" => {
          "monthly" => [
            ["2013-06", 3],
            ["2013-07", 0],
            ["2013-08", 4],
          ],
          "recent" => {
            "total" => 4,
            "daily" => [
              ["2013-08-02", 0],
              ["2013-08-03", 0],
              ["2013-08-04", 0],
              ["2013-08-05", 0],
              ["2013-08-06", 0],
              ["2013-08-07", 0],
              ["2013-08-08", 0],
              ["2013-08-09", 0],
              ["2013-08-10", 0],
              ["2013-08-11", 0],
              ["2013-08-12", 0],
              ["2013-08-13", 0],
              ["2013-08-14", 0],
              ["2013-08-15", 0],
              ["2013-08-16", 0],
              ["2013-08-17", 0],
              ["2013-08-18", 0],
              ["2013-08-19", 0],
              ["2013-08-20", 0],
              ["2013-08-21", 0],
              ["2013-08-22", 0],
              ["2013-08-23", 0],
              ["2013-08-24", 0],
              ["2013-08-25", 0],
              ["2013-08-26", 0],
              ["2013-08-27", 0],
              ["2013-08-28", 0],
              ["2013-08-29", 0],
              ["2013-08-30", 0],
              ["2013-08-31", 4],
            ],
          },
          "total" => 7,
        },
      },
      "api_backend_count" => 4,
      "organization_count" => 3,
      "api_backend_url_match_count" => 4,
    }, data.fetch("production_apis"))

    assert_equal([
      "all",
      "api_backend_count",
      "api_backend_url_match_count",
      "organization_count",
      "organizations",
    ].sort, data.fetch("production_apis").keys.sort)
  end

  def test_caches_results
    assert_equal(0, Cache.count)

    response = make_request
    assert_equal("MISS", response.headers["X-Cache"])
    assert_equal(2, Cache.count)

    response = make_request
    assert_equal("HIT", response.headers["X-Cache"])
    assert_equal(2, Cache.count)

    cache = Cache.find_by!(:id => "analytics_summary")
    assert_equal("analytics_summary", cache.id)
    assert_in_delta(Time.now.to_i, cache.created_at.to_i, 10)
    assert_in_delta(Time.now.to_i, cache.updated_at.to_i, 10)
    assert_nil(cache.expires_at)
    assert(cache.data)
    data = MultiJson.load(cache.data)
    assert_equal([
      "cached_at",
      "end_time",
      "production_apis",
      "start_time",
      "timezone",
    ].sort, data.keys.sort)
  end

  def test_unique_users_over_bucket_size_limit
    LogItem.clean_indices!

    override_config({
      opensearch: {
        max_buckets: 10,
      },
    }) do
      FactoryBot.create_list(:log_item, 3, request_at: @start_time, user_id: SecureRandom.uuid)
      15.times do
        FactoryBot.create(:log_item, request_at: @start_time, user_id: SecureRandom.uuid)
      end
      LogItem.refresh_indices!

      response = make_request
      assert_response_code(200, response)
      assert_equal("MISS", response.headers["X-Cache"])

      data = MultiJson.load(response.body)
      assert_equal(18, data.fetch("production_apis").fetch("all").fetch("hits").fetch("total"))
      assert_equal("2013-06", data.fetch("production_apis").fetch("all").fetch("hits").fetch("monthly")[0][0])
      assert_equal(18, data.fetch("production_apis").fetch("all").fetch("hits").fetch("monthly")[0][1])

      assert_equal(16, data.fetch("production_apis").fetch("all").fetch("active_api_keys").fetch("total"))
      assert_equal("2013-06", data.fetch("production_apis").fetch("all").fetch("active_api_keys").fetch("monthly")[0][0])
      assert_equal(16, data.fetch("production_apis").fetch("all").fetch("active_api_keys").fetch("monthly")[0][1])
    end
  end

  private

  def make_request(user = nil)
    user ||= FactoryBot.create(:api_user, :roles => ["api-umbrella-public-metrics"])

    Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v0/analytics/summary.json", http_options.deep_merge({
      :headers => { "X-Api-Key" => user.api_key },
    }))
  end
end

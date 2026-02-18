require_relative "../../../test_helper"

class Test::Apis::Admin::Stats::TestUsers < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
    @user1 = FactoryBot.create(:api_user)
    @user2 = FactoryBot.create(:api_user)
    LogItem.clean_indices!
  end

  def test_json
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-16T00:00:00.000Z").utc, :user_id => @user1.id)
    FactoryBot.create_list(:log_item, 1, :request_at => Time.parse("2015-01-17T00:00:00.000Z").utc, :user_id => @user2.id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/users.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "length" => "10",
      },
    }))

    assert_response_code(200, response)
    body = response.body
    data = MultiJson.load(body)
    assert_equal({
      "data" => [
        {
          "created_at" => @user1.created_at.utc.iso8601,
          "email" => @user1.email,
          "first_name" => @user1.first_name,
          "hits" => 2,
          "id" => @user1.id,
          "last_name" => @user1.last_name,
          "last_request_at" => "2015-01-16T00:00:00Z",
          "registration_source" => @user1.registration_source,
          "use_description" => @user1.use_description,
          "website" => @user1.website,
        },
        {
          "created_at" => @user2.created_at.utc.iso8601,
          "email" => @user2.email,
          "first_name" => @user2.first_name,
          "hits" => 1,
          "id" => @user2.id,
          "last_name" => @user2.last_name,
          "last_request_at" => "2015-01-17T00:00:00Z",
          "registration_source" => @user2.registration_source,
          "use_description" => @user2.use_description,
          "website" => @user2.website,
        },
      ],
      "draw" => 0,
      "recordsFiltered" => 2,
      "recordsTotal" => 2,
    }, data)
  end

  def test_csv_download
    FactoryBot.create_list(:log_item, 2, :request_at => Time.parse("2015-01-16T00:00:00.000Z").utc, :user_id => @user1.id)
    FactoryBot.create_list(:log_item, 1, :request_at => Time.parse("2015-01-17T00:00:00.000Z").utc, :user_id => @user2.id)
    LogItem.refresh_indices!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/users.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
      },
    }))

    assert_response_code(200, response)
    assert_equal("text/csv", response.headers["Content-Type"])
    assert_match("attachment; filename=\"api_users_#{Time.now.utc.strftime("%Y-%m-%d")}.csv\"", response.headers["Content-Disposition"])

    csv = CSV.parse(response.body)
    assert_equal(3, csv.length, csv)
    assert_equal([
      "Email",
      "First Name",
      "Last Name",
      "Website",
      "Registration Source",
      "Signed Up (UTC)",
      "Hits",
      "Last Request (UTC)",
      "Use Description",
    ], csv[0])
    assert_equal([
      @user1.email,
      @user1.first_name,
      @user1.last_name,
      @user1.website,
      @user1.registration_source,
      @user1.created_at.utc.iso8601,
      "2",
      "2015-01-16T00:00:00Z",
      @user1.use_description,
    ], csv[1])
    assert_equal([
      @user2.email,
      @user2.first_name,
      @user2.last_name,
      @user2.website,
      @user2.registration_source,
      @user2.created_at.utc.iso8601,
      "1",
      "2015-01-17T00:00:00Z",
      @user2.use_description,
    ], csv[2])
  end

  def test_no_results_non_existent_indices
    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/users.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2000-01-13",
        "end_at" => "2000-01-18",
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
end

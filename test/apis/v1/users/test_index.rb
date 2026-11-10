require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestIndex < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  include ApiUmbrellaSharedTests::DataTablesApi

  def test_response_fields
    record = FactoryBot.create(data_tables_factory_name, {
      :created_at => Time.utc(2017, 1, 1),
      :created_by_id => SecureRandom.uuid,
      :created_by_username => "creator@example.com",
      :disabled_at => Time.utc(2017, 1, 2),
      :email => "foo@example.com",
      :email_verified => true,
      :first_name => "Foo",
      :last_name => "Bar",
      :metadata => {
        "foo" => "bar",
      },
      :registration_ip => "127.0.0.10",
      :registration_key_creator_api_user_id => api_user.id,
      :registration_origin => "http://example.com",
      :registration_referer => "http://example.com/foo",
      :registration_source => "test",
      :registration_user_agent => "curl",
      :roles => ["role1", "role2"],
      :settings => FactoryBot.build(:custom_rate_limit_api_user_settings, {
        :rate_limits => [
          FactoryBot.build(:rate_limit, :duration => 5000, :limit_by => "ip", :limit_to => 10),
        ],
      }),
      :throttle_by_ip => true,
      :updated_at => Time.utc(2017, 1, 3),
      :updated_by_id => SecureRandom.uuid,
      :updated_by_username => "updater@example.com",
      :use_description => "Usage",
      :website => "http://foo.example.com",
    })

    response = Typhoeus.get(data_tables_api_url, http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => { :value => record.id },
      },
    }))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_data_tables_root_fields(data)
    assert_equal(1, data.fetch("data").length)

    record_data = data.fetch("data").first
    assert_base_record_fields(record_data)

    assert_equal("2017-01-01T00:00:00Z", record_data.fetch("created_at"))
    assert_equal(record.created_by_id, record_data.fetch("created_by"))
    assert_equal("creator@example.com", record_data.fetch("creator").fetch("username"))
    assert_equal("2017-01-02T00:00:00Z", record_data.fetch("disabled_at"))
    assert_equal("foo@example.com", record_data.fetch("email"))
    assert_equal(true, record_data.fetch("email_verified"))
    assert_equal(false, record_data.fetch("enabled"))
    assert_equal("Foo", record_data.fetch("first_name"))
    assert_equal("Bar", record_data.fetch("last_name"))
    assert_equal({ "foo" => "bar" }, record_data.fetch("metadata"))
    assert_equal("foo: bar", record_data.fetch("metadata_yaml_string"))
    assert_equal("127.0.0.10", record_data.fetch("registration_ip"))
    assert_equal(api_user.id, record_data.fetch("registration_key_creator_api_user_id"))
    assert_equal("http://example.com", record_data.fetch("registration_origin"))
    assert_equal("http://example.com/foo", record_data.fetch("registration_referer"))
    assert_equal("test", record_data.fetch("registration_source"))
    assert_equal("curl", record_data.fetch("registration_user_agent"))
    assert_equal(["role1", "role2"], record_data.fetch("roles"))
    assert_kind_of(Hash, record_data.fetch("settings"))
    assert_equal([
      "allowed_ips",
      "allowed_referers",
      "id",
      "rate_limit_mode",
      "rate_limits",
    ].sort, record_data.fetch("settings").keys.sort)
    assert_kind_of(Array, record_data.fetch("settings").fetch("rate_limits"))
    assert_equal(1, record_data.fetch("settings").fetch("rate_limits").length)
    assert_kind_of(Hash, record_data.fetch("settings").fetch("rate_limits").first)
    assert_equal([
      "_id",
      "accuracy",
      "distributed",
      "duration",
      "id",
      "limit",
      "limit_by",
      "response_headers",
    ].sort, record_data.fetch("settings").fetch("rate_limits").first.keys.sort)
    assert_equal(true, record_data.fetch("throttle_by_ip"))
    assert_equal(record.updated_by_id, record_data.fetch("updated_by"))
    assert_equal("test_example_admin_username", record_data.fetch("updater").fetch("username"))

    assert_equal("Usage", record_data.fetch("use_description"))
    assert_equal("http://foo.example.com", record_data.fetch("website"))
  end

  def test_empty_response_fields
    record = FactoryBot.create(data_tables_factory_name)

    response = Typhoeus.get(data_tables_api_url, http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => { :value => record.id },
      },
    }))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_data_tables_root_fields(data)
    assert_equal(1, data.fetch("data").length)

    record_data = data.fetch("data").first
    assert_base_record_fields(record_data)

    assert_equal("00000000-1111-2222-3333-444444444444", record_data.fetch("created_by"))
    assert_equal("test_example_admin_username", record_data.fetch("creator").fetch("username"))
    assert_nil(record_data.fetch("disabled_at"))
    assert_equal(false, record_data.fetch("email_verified"))
    assert_equal(true, record_data.fetch("enabled"))
    assert_nil(record_data.fetch("registration_ip"))
    assert_nil(record_data.fetch("registration_key_creator_api_user_id"))
    assert_nil(record_data.fetch("registration_origin"))
    assert_nil(record_data.fetch("registration_referer"))
    assert_nil(record_data.fetch("registration_source"))
    assert_nil(record_data.fetch("registration_user_agent"))
    assert_equal([], record_data.fetch("roles"))
    assert_nil(record_data.fetch("settings"))
    assert_equal(false, record_data.fetch("throttle_by_ip"))
    assert_equal("00000000-1111-2222-3333-444444444444", record_data.fetch("updated_by"))
    assert_equal("test_example_admin_username", record_data.fetch("updater").fetch("username"))
    assert_nil(record_data.fetch("use_description"))
    assert_nil(record_data.fetch("website"))
  end

  def test_includes_api_key_preview_not_full_api_key
    api_user = FactoryBot.create(:api_user)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token))
    assert_response_code(200, response)

    data = MultiJson.load(response.body)
    user = data["data"].find { |u| u["id"] == api_user.id }
    refute_includes(user.keys, "api_key")
    refute_includes(user.keys, "api_key_hides_at")
    assert_equal("#{api_user.api_key[0, 4]}...#{api_user.api_key[-4..]}", user["api_key_preview"])
  end

  def test_search_first_name
    assert_data_tables_search(:first_name, "FirstNameSearchTest", "irstnamesearcht")
  end

  def test_search_last_name
    assert_data_tables_search(:last_name, "LastNameSearchTest", "astnamesearcht")
  end

  def test_search_email
    assert_data_tables_search(:email, "EmailSearchTest@example.com", "mailsearchtest@exampl")
  end

  def test_search_api_key
    assert_data_tables_search(:api_key, "QhcfMp_API_KEY_SEARCH_TEST", "qhcfmp_ap")

    # Since the API key search is a bit special (the values are encrypted in
    # the database, so we only search by a prefix part that is stored
    # unencrypted), perform some further search tests.
    record = ApiUser.find_by!(:api_key_prefix => "QhcfMp_API_KEY_S")

    # Ensure the full string matches (even though it's longer than the prefix).
    assert_wildcard_search_match(:api_key, "QhcfMp_API_KEY_SEARCH_TEST", "qhcfmp_api_key_search_test", record)

    # Since we're matching based on the first 16 characters, then search
    # strings beyond 16 characters will still match the record, even though the
    # search value doesn't technically match the full API key (but that's okay,
    # since we assume the first 16 characters should still provide plenty of
    # uniqueness).
    assert_wildcard_search_match(:api_key, "API_KEY_SEARCH_TEST", "qhcfmp_api_key_sZZZ", record)
    refute_wildcard_search_match(:api_key, "API_KEY_SEARCH_TEST", "qhcfmp_api_key_ZZZ")

    # We only perform a prefix based search, rather than a full wildcard search
    # (since there's not really a reason to search for strings in the middle of
    # an API key).
    refute_wildcard_search_match(:api_key, "API_KEY_SEARCH_TEST", "cfmp_api_key")
    refute_wildcard_search_match(:api_key, "API_KEY_SEARCH_TEST", "pre_qhcfmp_api_key")
  end

  def test_search_registration_source
    assert_data_tables_search(:registration_source, "RegistrationSourceSearchTest", "egistrationsourcesearchtes")
  end

  def test_search_roles
    assert_data_tables_search(:roles, ["RoleSearchTest1", "RoleSearchTest2", "RoleSearchTest33"], "olesearchtest3")
  end

  def test_search_counts_with_role_joins
    assert_data_tables_search(:roles, ["#{unique_test_id}-role1", "#{unique_test_id}-role2", "#{unique_test_id}-role3"], "#{unique_test_id}-role")
  end

  def test_order_email
    assert_data_tables_order(:email, ["a@example.com", "b@example.com"])
  end

  def test_order_first_name
    assert_data_tables_order(:first_name, ["A", "B"])
  end

  def test_order_last_name
    assert_data_tables_order(:last_name, ["A", "B"])
  end

  def test_order_use_description
    assert_data_tables_order(:use_description, ["A", "B"])
  end

  def test_order_registration_source
    assert_data_tables_order(:registration_source, ["A", "B"])
  end

  def test_csv
    api_user = FactoryBot.create(:api_user)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users.csv", http_options.deep_merge(admin_token).deep_merge({
      :params => {
        :search => { :value => api_user.id },
      },
    }))
    assert_response_code(200, response)
    assert_equal("text/csv", response.headers["Content-Type"])
    assert_match("attachment; filename=\"users_#{Time.now.utc.strftime("%Y-%m-%d")}.csv\"", response.headers["Content-Disposition"])

    csv = CSV.parse(response.body)
    assert_equal(2, csv.length, csv)
    assert_equal([
      "E-mail",
      "First Name",
      "Last Name",
      "Purpose",
      "Created",
      "Registration Source",
      "API Key",
    ], csv[0])
    assert_equal([
      api_user.email,
      api_user.first_name,
      api_user.last_name,
      api_user.use_description,
      api_user.created_at.utc.iso8601,
      api_user.registration_source,
      api_user.api_key_preview,
    ], csv[1])
  end

  private

  def data_tables_api_url
    "https://127.0.0.1:9081/api-umbrella/v1/users.json"
  end

  def data_tables_factory_name
    :api_user
  end

  def data_tables_record_count
    ApiUser.count
  end

  def assert_base_record_fields(record_data)
    assert_equal([
      "api_key_preview",
      "created_at",
      "created_by",
      "creator",
      "deleted_at",
      "disabled_at",
      "email",
      "email_verified",
      "enabled",
      "first_name",
      "id",
      "last_name",
      "metadata",
      "metadata_yaml_string",
      "registration_ip",
      "registration_key_creator_api_user_id",
      "registration_origin",
      "registration_referer",
      "registration_source",
      "registration_user_agent",
      "roles",
      "settings",
      "throttle_by_ip",
      "ts",
      "updated_at",
      "updated_by",
      "updater",
      "use_description",
      "version",
      "website",
    ].sort, record_data.keys.sort)
    assert_kind_of(String, record_data.fetch("api_key_preview"))
    assert_equal(11, record_data.fetch("api_key_preview").length)
    assert_match_iso8601(record_data.fetch("created_at"))
    assert_match_uuid(record_data.fetch("created_by"))
    assert_kind_of(Hash, record_data.fetch("creator"))
    assert_equal(["username"].sort, record_data.fetch("creator").keys)
    assert_kind_of(String, record_data.fetch("creator").fetch("username"))
    assert_nil(record_data.fetch("deleted_at"))
    assert_kind_of(String, record_data.fetch("email"))
    assert_kind_of(String, record_data.fetch("first_name"))
    assert_match_uuid(record_data.fetch("id"))
    assert_kind_of(String, record_data.fetch("last_name"))
    assert_kind_of(Hash, record_data.fetch("ts"))
    assert_equal(["$timestamp"].sort, record_data.fetch("ts").keys.sort)
    assert_kind_of(Hash, record_data.fetch("ts").fetch("$timestamp"))
    assert_equal(["i", "t"].sort, record_data.fetch("ts").fetch("$timestamp").keys.sort)
    assert_kind_of(Integer, record_data.fetch("ts").fetch("$timestamp").fetch("i"))
    assert_kind_of(Integer, record_data.fetch("ts").fetch("$timestamp").fetch("t"))
    assert_match_iso8601(record_data.fetch("updated_at"))
    assert_match_uuid(record_data.fetch("updated_by"))
    assert_kind_of(Hash, record_data.fetch("updater"))
    assert_equal(["username"].sort, record_data.fetch("updater").keys)
    assert_kind_of(String, record_data.fetch("updater").fetch("username"))
    assert_kind_of(Integer, record_data.fetch("version"))
  end
end

require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestPermissions < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::AdminPermissions
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_no_admin_and_api_key_with_key_creator_role
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    }).api_key
    admin = nil
    assert_admin_permitted_create_only(api_key, admin)
  end

  def test_no_admin_and_api_key_without_key_creator_role
    api_key = FactoryBot.create(:api_user).api_key
    admin = nil
    assert_admin_forbidden(api_key, admin)
  end

  def test_no_admin_and_no_api_key
    api_key = nil
    admin = nil
    assert_admin_forbidden(api_key, admin)
  end

  def test_superuser_admin_and_api_key_with_key_creator_role
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    }).api_key
    admin = FactoryBot.create(:admin)
    assert_admin_permitted(api_key, admin)
  end

  def test_superuser_admin_and_api_key_without_key_creator_role
    api_key = FactoryBot.create(:api_user).api_key
    admin = FactoryBot.create(:admin)
    assert_admin_permitted(api_key, admin)
  end

  def test_superuser_admin_and_no_api_key
    api_key = nil
    admin = FactoryBot.create(:admin)
    assert_admin_forbidden(api_key, admin)
  end

  def test_view_manage_admin_and_api_key_with_key_creator_role
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    }).api_key
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_and_manage_permission),
    ])
    assert_admin_permitted(api_key, admin)
  end

  def test_view_manage_admin_and_api_key_without_key_creator_role
    api_key = FactoryBot.create(:api_user).api_key
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_and_manage_permission),
    ])
    assert_admin_permitted(api_key, admin)
  end

  def test_view_manage_admin_and_no_api_key
    api_key = nil
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_and_manage_permission),
    ])
    assert_admin_forbidden(api_key, admin)
  end

  def test_view_admin_and_api_key_with_key_creator_role
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    }).api_key
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_permission),
    ])
    assert_admin_permitted_view_only(api_key, admin)
  end

  def test_view_admin_and_api_key_without_key_creator_role
    api_key = FactoryBot.create(:api_user).api_key
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_permission),
    ])
    assert_admin_permitted_view_only(api_key, admin)
  end

  def test_view_admin_and_no_api_key
    api_key = nil
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_permission),
    ])
    assert_admin_forbidden(api_key, admin)
  end

  def test_manage_admin_and_api_key_with_key_creator_role
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    }).api_key
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_manage_permission),
    ])
    assert_admin_permitted_manage_only(api_key, admin)
  end

  def test_manage_admin_and_api_key_without_key_creator_role
    api_key = FactoryBot.create(:api_user).api_key
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_manage_permission),
    ])
    assert_admin_permitted_manage_only(api_key, admin)
  end

  def test_manage_admin_and_no_api_key
    api_key = nil
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_permission),
    ])
    assert_admin_forbidden(api_key, admin)
  end

  def test_non_admin_exact_role_needed
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator-bogus", "bogus-api-umbrella-key-creator"],
    }).api_key
    admin = nil
    assert_admin_forbidden(api_key, admin)
  end

  def test_non_admin_ignores_private_fields
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    }).api_key
    admin = nil
    initial_count = active_count

    attributes = FactoryBot.attributes_for(:api_user, {
      :roles => ["new-role#{rand(999_999)}"],
      :settings => {
        :rate_limit_mode => "unlimited",
      },
    }).deep_stringify_keys
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options(api_key, admin).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))

    assert_response_code(201, response)
    assert_equal(1, active_count - initial_count)
    data = MultiJson.load(response.body)
    record = ApiUser.find(data["user"]["id"])
    assert_equal([], record.roles)
    assert_nil(record.settings)
  end

  def test_admin_uses_private_fields
    api_key = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    }).api_key
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :user_view_and_manage_permission),
    ])
    initial_count = active_count

    attributes = FactoryBot.attributes_for(:api_user, {
      :roles => ["new-role#{rand(999_999)}"],
      :settings => {
        :rate_limit_mode => "unlimited",
      },
    }).deep_stringify_keys
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options(api_key, admin).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))

    assert_response_code(201, response)
    assert_equal(1, active_count - initial_count)
    data = MultiJson.load(response.body)
    record = ApiUser.find(data["user"]["id"])
    refute_nil(record.roles)
    assert_equal(attributes["roles"], record.roles)
    assert_equal("unlimited", record.settings.rate_limit_mode)
  end

  private

  def assert_admin_permitted(api_key, admin)
    assert_admin_permitted_index(api_key, admin)
    assert_admin_permitted_show(api_key, admin)
    assert_admin_permitted_create(api_key, admin)
    assert_admin_permitted_update(api_key, admin)
    assert_no_destroy(api_key, admin)
    assert_admin_permitted_request_deactivation(api_key, admin)
    assert_admin_permitted_show_confirm_deactivation(api_key, admin)
    assert_admin_permitted_confirm_deactivation(api_key, admin)
  end

  def assert_admin_permitted_create_only(api_key, admin)
    assert_admin_forbidden_index(api_key, admin)
    assert_admin_forbidden_show(api_key, admin)
    assert_admin_permitted_create(api_key, admin)
    assert_admin_forbidden_update(api_key, admin)
    assert_no_destroy(api_key, admin)
    assert_admin_permitted_request_deactivation(api_key, admin)
    assert_admin_permitted_show_confirm_deactivation(api_key, admin)
    assert_admin_permitted_confirm_deactivation(api_key, admin)
  end

  def assert_admin_permitted_view_only(api_key, admin)
    assert_admin_permitted_index(api_key, admin)
    assert_admin_permitted_show(api_key, admin)
    assert_admin_forbidden_create(api_key, admin, :role_based_error => true)
    assert_admin_forbidden_update(api_key, admin, :role_based_error => true)
    assert_no_destroy(api_key, admin)
    assert_admin_forbidden_request_deactivation(api_key, admin, :role_based_error => true)
    assert_admin_forbidden_show_confirm_deactivation(api_key, admin, :role_based_error => true)
    assert_admin_forbidden_confirm_deactivation(api_key, admin, :role_based_error => true)
  end

  def assert_admin_permitted_manage_only(api_key, admin)
    assert_admin_forbidden_index(api_key, admin, :role_based_error => true)
    assert_admin_forbidden_show(api_key, admin, :role_based_error => true)
    assert_admin_permitted_create(api_key, admin)
    assert_admin_permitted_update(api_key, admin)
    assert_no_destroy(api_key, admin)
    assert_admin_permitted_request_deactivation(api_key, admin)
    assert_admin_permitted_show_confirm_deactivation(api_key, admin)
    assert_admin_permitted_confirm_deactivation(api_key, admin)
  end

  def assert_admin_forbidden(api_key, admin)
    assert_admin_forbidden_index(api_key, admin)
    assert_admin_forbidden_show(api_key, admin)
    assert_admin_forbidden_create(api_key, admin)
    assert_admin_forbidden_update(api_key, admin)
    assert_no_destroy(api_key, admin)
    assert_admin_forbidden_request_deactivation(api_key, admin)
    assert_admin_forbidden_show_confirm_deactivation(api_key, admin)
    assert_admin_forbidden_confirm_deactivation(api_key, admin)
  end

  def assert_admin_permitted_index(api_key, admin)
    record = FactoryBot.create(:api_user)
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options(api_key, admin))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    record_ids = data["data"].map { |r| r["id"] }
    assert_includes(record_ids, record.id)
  end

  def assert_admin_forbidden_index(api_key, admin, role_based_error: false)
    FactoryBot.create(:api_user)
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options(api_key, admin))

    if(role_based_error)
      assert_response_code(200, response)
      data = MultiJson.load(response.body)
      assert_equal([], data["data"])
    else
      if(api_key)
        assert_response_code(401, response)
      else
        assert_response_code(403, response)
      end
      data = MultiJson.load(response.body)
      assert_equal(["error"], data.keys)
    end
  end

  def assert_admin_permitted_show(api_key, admin)
    record = FactoryBot.create(:api_user)
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users/#{record.id}.json", http_options(api_key, admin))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(["user"], data.keys)
  end

  def assert_admin_forbidden_show(api_key, admin, role_based_error: false)
    record = FactoryBot.create(:api_user)
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users/#{record.id}.json", http_options(api_key, admin))

    if(role_based_error)
      assert_response_code(403, response)
      data = MultiJson.load(response.body)
      assert_equal(["errors"], data.keys)
    else
      if(api_key)
        assert_response_code(401, response)
      else
        assert_response_code(403, response)
      end
      data = MultiJson.load(response.body)
      assert_equal(["error"], data.keys)
    end
  end

  def assert_admin_permitted_create(api_key, admin)
    attributes = FactoryBot.attributes_for(:api_user).deep_stringify_keys
    initial_count = active_count
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options(api_key, admin).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))

    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    refute_nil(data["user"]["first_name"])
    assert_equal(attributes["first_name"], data["user"]["first_name"])
    assert_equal(1, active_count - initial_count)
  end

  def assert_admin_forbidden_create(api_key, admin, role_based_error: false)
    attributes = FactoryBot.attributes_for(:api_user).deep_stringify_keys
    initial_count = active_count
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options(api_key, admin).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))

    if(role_based_error)
      assert_response_code(403, response)
      data = MultiJson.load(response.body)
      assert_equal(["errors"], data.keys)
    else
      if(api_key)
        assert_response_code(401, response)
      else
        assert_response_code(403, response)
      end
      data = MultiJson.load(response.body)
      assert_equal(["error"], data.keys)
    end
    assert_equal(0, active_count - initial_count)
  end

  def assert_admin_permitted_update(api_key, admin)
    record = FactoryBot.create(:api_user)

    attributes = record.serializable_hash
    attributes["first_name"] += rand(999_999).to_s
    response = Typhoeus.put("https://127.0.0.1:9081/api-umbrella/v1/users/#{record.id}.json", http_options(api_key, admin).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))

    assert_response_code(200, response)
    record = ApiUser.find(record.id)
    refute_nil(record.first_name)
    assert_equal(attributes["first_name"], record.first_name)
  end

  def assert_admin_forbidden_update(api_key, admin, role_based_error: false)
    record = FactoryBot.create(:api_user)

    attributes = record.serializable_hash
    attributes["first_name"] += rand(999_999).to_s
    response = Typhoeus.put("https://127.0.0.1:9081/api-umbrella/v1/users/#{record.id}.json", http_options(api_key, admin).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))

    if(role_based_error)
      assert_response_code(403, response)
      data = MultiJson.load(response.body)
      assert_equal(["errors"], data.keys)
    else
      if(api_key)
        assert_response_code(401, response)
      else
        assert_response_code(403, response)
      end
      data = MultiJson.load(response.body)
      assert_equal(["error"], data.keys)
    end

    record = ApiUser.find(record.id)
    refute_nil(record.first_name)
    refute_equal(attributes["first_name"], record.first_name)
  end

  def assert_no_destroy(api_key, admin)
    record = FactoryBot.create(:api_user)
    initial_count = active_count
    response = Typhoeus.delete("https://127.0.0.1:9081/api-umbrella/v1/users/#{record.id}.json", http_options(api_key, admin))

    if(api_key)
      assert_response_code(404, response)
    else
      assert_response_code(403, response)
    end
    assert_equal(0, active_count - initial_count)
  end

  def assert_admin_permitted_request_deactivation(api_key, admin)
    record = FactoryBot.create(:api_user)

    attributes = { api_key: record.api_key, email: record.email }
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users/request-deactivation.json", http_options(api_key, admin).deep_merge({
      headers: { "Content-Type" => "application/json" },
      body: MultiJson.dump(user: attributes),
    }))

    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert(data.fetch("user").fetch("deactivation_sent_at"))
    record.reload
    assert(record.deactivation_token_hash)
  end

  def assert_admin_forbidden_request_deactivation(api_key, admin, role_based_error: false)
    record = FactoryBot.create(:api_user)

    attributes = { api_key: record.api_key, email: record.email }
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users/request-deactivation.json", http_options(api_key, admin).deep_merge({
      headers: { "Content-Type" => "application/json" },
      body: MultiJson.dump(user: attributes),
    }))

    if(role_based_error)
      assert_response_code(403, response)
      data = MultiJson.load(response.body)
      assert_equal(["errors"], data.keys)
    else
      if(api_key)
        assert_response_code(401, response)
      else
        assert_response_code(403, response)
      end
      data = MultiJson.load(response.body)
      assert_equal(["error"], data.keys)
    end
    record.reload
    assert_nil(record.deactivation_token_hash)
  end

  def assert_admin_permitted_show_confirm_deactivation(api_key, admin)
    record = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users/confirm-deactivation.json", http_options(api_key, admin).deep_merge({
      headers: { "Content-Type" => "application/json" },
      params: { token: record.deactivation_token },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert(data.fetch("user").fetch("api_key_suffix"))
  end

  def assert_admin_forbidden_show_confirm_deactivation(api_key, admin, role_based_error: false)
    record = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)

    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users/confirm-deactivation.json", http_options(api_key, admin).deep_merge({
      headers: { "Content-Type" => "application/json" },
      params: { token: record.deactivation_token },
    }))

    if(role_based_error)
      assert_response_code(403, response)
      data = MultiJson.load(response.body)
      assert_equal(["errors"], data.keys)
    else
      if(api_key)
        assert_response_code(401, response)
      else
        assert_response_code(403, response)
      end
      data = MultiJson.load(response.body)
      assert_equal(["error"], data.keys)
    end
  end

  def assert_admin_permitted_confirm_deactivation(api_key, admin)
    record = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users/confirm-deactivation.json", http_options(api_key, admin).deep_merge({
      headers: { "Content-Type" => "application/json" },
      body: MultiJson.dump(user: { deactivation_token: record.deactivation_token }),
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert(data.fetch("user").fetch("api_key_suffix"))
  end

  def assert_admin_forbidden_confirm_deactivation(api_key, admin, role_based_error: false)
    record = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users/confirm-deactivation.json", http_options(api_key, admin).deep_merge({
      headers: { "Content-Type" => "application/json" },
      body: MultiJson.dump(user: { deactivation_token: record.deactivation_token }),
    }))

    if(role_based_error)
      assert_response_code(403, response)
      data = MultiJson.load(response.body)
      assert_equal(["errors"], data.keys)
    else
      if(api_key)
        assert_response_code(401, response)
      else
        assert_response_code(403, response)
      end
      data = MultiJson.load(response.body)
      assert_equal(["error"], data.keys)
    end
  end

  def http_options(api_key, admin)
    options = @@http_options.deep_dup

    if(api_key)
      options.deep_merge!({
        :headers => {
          "X-Api-Key" => api_key,
        },
      })
    else
      options[:headers].delete("X-Api-Key")
      assert_nil(options[:headers]["X-Api-Key"])
    end

    if(admin)
      options.deep_merge!(admin_token(admin))
    else
      options[:headers].delete("X-Admin-Auth-Token")
      assert_nil(options[:headers]["X-Admin-Auth-Token"])
    end

    options
  end

  def active_count
    ApiUser.count
  end
end

require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestCreate < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_valid_create
    non_admin_auth = non_admin_key_creator_api_key
    attributes = FactoryBot.attributes_for(:api_user)
    initial_count = active_count
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_auth).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => { :user => attributes },
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal(attributes[:last_name], data["user"]["last_name"])

    user = ApiUser.find(data["user"]["id"])
    assert_equal(attributes[:last_name], user.last_name)

    assert_equal(1, active_count - initial_count)
  end

  def test_api_key_format
    attributes = FactoryBot.attributes_for(:api_user)
    refute(attributes["api_key"])

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => { :user => attributes },
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert(data["user"]["api_key"])
    assert_equal(40, data["user"]["api_key"].length)
    assert_match(/\A[0-9A-Za-z]+\z/, data["user"]["api_key"])
  end

  def test_no_user_attributes_error
    non_admin_auth = non_admin_key_creator_api_key
    initial_count = active_count
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_auth).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => nil,
    }))
    assert_response_code(422, response)

    data = MultiJson.load(response.body)
    assert_equal(["errors"], data.keys)
    assert_equal(0, active_count - initial_count)
  end

  def test_user_attributes_unexpected_object_error
    non_admin_auth = non_admin_key_creator_api_key
    initial_count = active_count
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_auth).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => { :user => "something" },
    }))

    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal(["errors"], data.keys)
    assert_equal(0, active_count - initial_count)
  end

  def test_wildcard_cors
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => { :user => FactoryBot.attributes_for(:api_user) },
    }))
    assert_response_code(201, response)
    assert_equal("*", response.headers["Access-Control-Allow-Origin"])
  end

  def test_cors_preflight
    response = Typhoeus.options("https://127.0.0.1:9081/api-umbrella/v1/users.json", keyless_http_options)
    assert_response_code(204, response)
    assert_equal("Content-Type, X-Api-Key", response.headers["Access-Control-Allow-Headers"])
    assert_equal("POST, OPTIONS", response.headers["Access-Control-Allow-Methods"])
    assert_equal("*", response.headers["Access-Control-Allow-Origin"])
    assert_equal("600", response.headers["Access-Control-Max-Age"])
  end

  def test_permits_private_roles_field_as_admin
    attributes = FactoryBot.attributes_for(:api_user, :roles => ["admin"])
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal(["admin"], data["user"]["roles"])
    user = ApiUser.find(data["user"]["id"])
    assert_equal(["admin"], user.roles)
  end

  def test_ignores_private_roles_field_as_non_admin
    attributes = FactoryBot.attributes_for(:api_user, :roles => ["admin"])
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal([], data["user"]["roles"])
    user = ApiUser.find(data["user"]["id"])
    assert_equal([], user.roles)
  end

  def test_permits_private_metadata_field_as_admin
    attributes = FactoryBot.attributes_for(:api_user, :metadata => { "foo" => "bar" })
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal({ "foo" => "bar" }, data["user"]["metadata"])
    user = ApiUser.find(data["user"]["id"])
    assert_equal({ "foo" => "bar" }, user.metadata)
  end

  def test_ignores_private_metadata_field_as_non_admin
    attributes = FactoryBot.attributes_for(:api_user, :metadata => { "foo" => "bar" })
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_nil(data["user"]["metadata"])
    user = ApiUser.find(data["user"]["id"])
    assert_nil(user.metadata)
  end

  def test_permits_private_metadata_yaml_string_field_as_admin
    attributes = FactoryBot.attributes_for(:api_user, :metadata_yaml_string => "foo: bar")
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal({ "foo" => "bar" }, data["user"]["metadata"])
    user = ApiUser.find(data["user"]["id"])
    assert_equal({ "foo" => "bar" }, user.metadata)
  end

  def test_ignores_private_metadata_yaml_string_field_as_non_admin
    attributes = FactoryBot.attributes_for(:api_user, :metadata_yaml_string => "foo: bar")
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_nil(data["user"]["metadata"])
    user = ApiUser.find(data["user"]["id"])
    assert_nil(user.metadata)
  end

  def test_registration_source_default
    attributes = FactoryBot.attributes_for(:api_user)
    assert_nil(attributes[:registration_source])
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => { :user => attributes },
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal("api", data["user"]["registration_source"])
  end

  def test_registration_source_custom
    attributes = FactoryBot.attributes_for(:api_user, :registration_source => "whatever")
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => { :user => attributes },
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal("whatever", data["user"]["registration_source"])
  end

  def test_captures_and_returns_requester_details_as_admin
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => {
        "Content-Type" => "application/x-www-form-urlencoded",
        "X-Forwarded-For" => "1.2.3.4",
        "User-Agent" => "foo",
        "Referer" => "http://example.com/foo",
        "Origin" => "http://example.com",
      },
      :body => { :user => attributes },
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal("1.2.3.4", data["user"]["registration_ip"])
    assert_equal("foo", data["user"]["registration_user_agent"])
    assert_equal("http://example.com/foo", data["user"]["registration_referer"])
    assert_equal("http://example.com", data["user"]["registration_origin"])
    assert_equal(api_user.id, data["user"]["registration_key_creator_api_user_id"])

    user = ApiUser.find(data["user"]["id"])
    assert_equal(IPAddr.new("1.2.3.4"), user.registration_ip)
    assert_equal("foo", user.registration_user_agent)
    assert_equal("http://example.com/foo", user.registration_referer)
    assert_equal("http://example.com", user.registration_origin)
    assert_equal(api_user.id, user.registration_key_creator_api_user_id)
  end

  def test_captures_does_not_return_requester_details_as_non_admin
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => {
        "Content-Type" => "application/x-www-form-urlencoded",
        "X-Forwarded-For" => "1.2.3.4",
        "User-Agent" => "foo",
        "Referer" => "http://example.com/foo",
        "Origin" => "http://example.com",
      },
      :body => { :user => attributes },
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_nil(data["user"]["registration_ip"])
    assert_nil(data["user"]["registration_user_agent"])
    assert_nil(data["user"]["registration_referer"])
    assert_nil(data["user"]["registration_origin"])
    assert_nil(data["user"]["registration_key_creator_api_user_id"])

    user = ApiUser.find(data["user"]["id"])
    assert_equal(IPAddr.new("1.2.3.4"), user.registration_ip)
    assert_equal("foo", user.registration_user_agent)
    assert_equal("http://example.com/foo", user.registration_referer)
    assert_equal("http://example.com", user.registration_origin)
    assert_equal(@non_admin_key_creator_api_user.id, user.registration_key_creator_api_user_id)
  end

  def test_registration_ip_x_forwarded_last_trusted
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => {
        "Content-Type" => "application/x-www-form-urlencoded",
        "X-Forwarded-For" => "1.1.1.1, 2.2.2.2, 127.0.0.1",
        "User-Agent" => "foo",
        "Referer" => "https://example.com/foo",
        "Origin" => "https://example.com",
      },
      :body => { :user => attributes },
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal("2.2.2.2", data["user"]["registration_ip"])
  end

  def test_custom_rate_limits_reject_same_duration_and_limit_by
    attributes = FactoryBot.attributes_for(:api_user, {
      :settings => FactoryBot.attributes_for(:custom_rate_limit_api_user_settings, {
        :rate_limits => [
          FactoryBot.attributes_for(:rate_limit, :duration => 5000, :limit_by => "ip", :limit_to => 10),
          FactoryBot.attributes_for(:rate_limit, :duration => 5000, :limit_by => "ip", :limit_to => 20),
        ],
      }),
    })

    initial_count = active_count
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(422, response)

    data = MultiJson.load(response.body)
    assert_equal(["errors"], data.keys)

    assert_equal(0, active_count - initial_count)
  end

  def test_custom_rate_limits_accept_same_duration_different_limit_by
    attributes = FactoryBot.attributes_for(:api_user, {
      :settings => FactoryBot.attributes_for(:custom_rate_limit_api_user_settings, {
        :rate_limits => [
          FactoryBot.attributes_for(:rate_limit, :duration => 5000, :limit_by => "ip", :limit_to => 10),
          FactoryBot.attributes_for(:rate_limit, :duration => 5000, :limit_by => "api_key", :limit_to => 20),
        ],
      }),
    })

    initial_count = active_count
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal(2, data["user"]["settings"]["rate_limits"].length)

    user = ApiUser.find(data["user"]["id"])
    assert_equal(2, user.settings.rate_limits.length)

    assert_equal(1, active_count - initial_count)
  end

  def test_validates_first_name_length
    response = make_request(:first_name => "a" * 80)
    assert_response_code(201, response)

    response = make_request(:first_name => "a" * 81)
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "first_name",
        "message" => "is too long (maximum is 80 characters)",
        "full_message" => "First name: is too long (maximum is 80 characters)",
      }],
    }, data)
  end

  def test_validates_first_name_format
    response = make_request(:first_name => "wwx")
    assert_response_code(201, response)

    [
      "http",
      "http:",
      "https",
      "https:",
      "www",
      "www.",
      "WwW.",
      "<",
      ">",
      "test\rtest",
      "test\ntest",
    ].each do |bad|
      response = make_request(:first_name => bad)
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "first_name",
          "message" => "is invalid",
          "full_message" => "First name: is invalid",
        }],
      }, data)
    end
  end

  def test_validates_first_name_format_configurable
    response = make_request(:first_name => "foobar")
    assert_response_code(201, response)

    response = make_request(:first_name => "FOOBAR")
    assert_response_code(201, response)

    response = make_request(:first_name => "http")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "first_name",
        "message" => "is invalid",
        "full_message" => "First name: is invalid",
      }],
    }, data)

    override_config({
      "web" => {
        "api_user" => {
          "first_name_exclude_regex" => "foobar",
        },
      },
    }) do
      response = make_request(:first_name => "foobar")
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "first_name",
          "message" => "is invalid",
          "full_message" => "First name: is invalid",
        }],
      }, data)

      response = make_request(:first_name => "FOOBAR")
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "first_name",
          "message" => "is invalid",
          "full_message" => "First name: is invalid",
        }],
      }, data)

      response = make_request(:first_name => "http")
      assert_response_code(201, response)
    end
  end

  def test_validates_last_name_length
    response = make_request(:last_name => "a" * 80)
    assert_response_code(201, response)

    response = make_request(:last_name => "a" * 81)
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "last_name",
        "message" => "is too long (maximum is 80 characters)",
        "full_message" => "Last name: is too long (maximum is 80 characters)",
      }],
    }, data)
  end

  def test_validates_last_name_format
    response = make_request(:last_name => "wwx")
    assert_response_code(201, response)

    [
      "http",
      "http:",
      "https",
      "https:",
      "www",
      "www.",
      "WwW.",
      "<",
      ">",
      "test\rtest",
      "test\ntest",
    ].each do |bad|
      response = make_request(:last_name => bad)
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "last_name",
          "message" => "is invalid",
          "full_message" => "Last name: is invalid",
        }],
      }, data)
    end
  end

  def test_validates_last_name_format_configurable
    response = make_request(:last_name => "foobar")
    assert_response_code(201, response)

    response = make_request(:last_name => "FOOBAR")
    assert_response_code(201, response)

    response = make_request(:last_name => "http")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "last_name",
        "message" => "is invalid",
        "full_message" => "Last name: is invalid",
      }],
    }, data)

    override_config({
      "web" => {
        "api_user" => {
          "last_name_exclude_regex" => "foobar",
        },
      },
    }) do
      response = make_request(:last_name => "foobar")
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "last_name",
          "message" => "is invalid",
          "full_message" => "Last name: is invalid",
        }],
      }, data)

      response = make_request(:last_name => "FOOBAR")
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "last_name",
          "message" => "is invalid",
          "full_message" => "Last name: is invalid",
        }],
      }, data)

      response = make_request(:last_name => "http")
      assert_response_code(201, response)
    end
  end

  def test_validates_email_length
    response = make_request(:email => "#{"a" * 249}@a.com")
    assert_response_code(201, response)

    response = make_request(:email => "#{"a" * 250}@a.com")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "email",
        "message" => "is too long (maximum is 255 characters)",
        "full_message" => "Email: is too long (maximum is 255 characters)",
      }],
    }, data)
  end

  def test_validates_email_format
    response = make_request(:email => "foo@example.com")
    assert_response_code(201, response)

    [
      " foo@example.com",
      "foo@example.com ",
      "foo@example.com\r",
      "foo@example.com\n",
      "foo@\rexample.com",
      "foo@example .com",
      "foo@ example.com",
      "foo @example.com",
      "foo@example",
      "@example.com",
      "@example",
      "foo@.com",
    ].each do |bad|
      response = make_request(:email => bad)
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "email",
          "message" => "Provide a valid email address.",
          "full_message" => "Email: Provide a valid email address.",
        }],
      }, data)
    end
  end

  def test_validates_email_format_configurable
    response = make_request(:email => "foo@example.com")
    assert_response_code(201, response)

    response = make_request(:email => "foo@EXAMPLE.com")
    assert_response_code(201, response)

    override_config({
      "web" => {
        "api_user" => {
          "email_regex" => "\\A[^@\\s]+@(?!example\\.com)[^@\\s]+\\.[^@\\s]+\\z",
        },
      },
    }) do
      response = make_request(:email => "foo@example.com")
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "email",
          "message" => "Provide a valid email address.",
          "full_message" => "Email: Provide a valid email address.",
        }],
      }, data)

      response = make_request(:email => "foo@EXAMPLE.com")
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "email",
          "message" => "Provide a valid email address.",
          "full_message" => "Email: Provide a valid email address.",
        }],
      }, data)
    end
  end

  def test_validates_website_length
    response = make_request(:website => "https://example.com/#{"a" * 235}")
    assert_response_code(201, response)

    response = make_request(:website => "https://example.com/#{"a" * 236}")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "website",
        "message" => "is too long (maximum is 255 characters)",
        "full_message" => "Website: is too long (maximum is 255 characters)",
      }],
    }, data)
  end

  def test_json_body
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal(attributes[:email], data["user"]["email"])
  end

  # Test behavior that the Rails "wrap_parameters" feature has on accepting
  # JSON params.
  def test_non_wrapped_json_body
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal(attributes[:email], data["user"]["email"])
  end

  def test_non_wrapped_json_body_null_wrapper
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes.deep_merge("user" => nil)),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal(attributes[:email], data["user"]["email"])
  end

  def test_non_wrapped_json_body_false_wrapper
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes.deep_merge("user" => false)),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    assert_equal(attributes[:email], data["user"]["email"])
  end

  def test_non_wrapped_json_body_empty_string_wrapper
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes.deep_merge(:user => "")),
    }))
    assert_response_code(422, response)
  end

  def test_non_wrapped_json_body_empty_hash_wrapper
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes.deep_merge(:user => {})),
    }))
    assert_response_code(422, response)
  end

  def test_non_wrapped_json_body_invalid_type_wrapper
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes.deep_merge(:user => 0)),
    }))
    assert_response_code(422, response)
  end

  def test_non_wrapped_json_body_invalid_values_wrapper
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes.deep_merge(:user => { :name => "" })),
    }))
    assert_response_code(422, response)
  end

  def test_conflicting_wrapped_and_non_wrapped_json_body
    attributes1 = FactoryBot.attributes_for(:api_user)
    attributes2 = FactoryBot.attributes_for(:api_user)
    refute_equal(attributes1[:email], attributes2[:email])

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(attributes1.deep_merge(:user => attributes2)),
    }))
    assert_response_code(201, response)

    # Pre-wrapped item should win, ignoring root attributes.
    data = MultiJson.load(response.body)
    assert_equal(attributes2[:email], data["user"]["email"])
  end

  # Wrapping only happens for JSON bodies.
  def test_non_wrapped_form_encoded_body
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => attributes,
    }))
    assert_response_code(422, response)
  end

  def test_rejects_empty_user_agent_for_non_admins
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => {
        "Content-Type" => "application/json",
        "Referer" => "https://localhost/signup/",
        "User-Agent" => "",
      },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(422, response)
  end

  def test_accepts_empty_user_agent_for_admins
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => {
        "Content-Type" => "application/json",
        "Referer" => "https://localhost/signup/",
        "User-Agent" => "",
      },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)
  end

  def test_rejects_empty_origin_for_non_admins
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => {
        "Content-Type" => "application/json",
        "Referer" => "https://localhost/signup/",
        "Origin" => "",
      },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "UNEXPECTED_ERROR",
        "message" => "An unexpected error occurred during signup. Please try again or contact us for assistance.",
      }],
    }, data)
  end

  def test_accepts_empty_origin_for_admins
    attributes = FactoryBot.attributes_for(:api_user)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => {
        "Content-Type" => "application/json",
        "Referer" => "https://localhost/signup/",
        "Origin" => "",
      },
      :body => MultiJson.dump(:user => attributes),
    }))
    assert_response_code(201, response)
  end

  def test_registration_options_not_set
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :user => FactoryBot.attributes_for(:api_user),
      }),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    user = ApiUser.find(data["user"]["id"])
    assert_equal({
      "site_name" => "API Umbrella",
    }, user.registration_options)
    assert_nil(user.registration_input_options)
  end

  def test_registration_options_empty
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :user => FactoryBot.attributes_for(:api_user),
        :options => {},
      }),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    user = ApiUser.find(data["user"]["id"])
    assert_equal({
      "site_name" => "API Umbrella",
    }, user.registration_options)
    assert_nil(user.registration_input_options)
  end

  def test_registration_options_set
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :user => FactoryBot.attributes_for(:api_user),
        :options => {
          :foo => "bar",
          :send_welcome_email => true,
          :contact_url => "example@#{unique_test_hostname}",
          :email_from_address => "example@127.0.0.1",
        },
      }),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    user = ApiUser.find(data["user"]["id"])
    assert_equal({
      "foo" => "bar",
      "send_welcome_email" => true,
      "email_from_address" => "example@127.0.0.1",
      "site_name" => "API Umbrella",
    }, user.registration_options)
    assert_equal({
      "foo" => "bar",
      "send_welcome_email" => true,
      "contact_url" => "example@#{unique_test_hostname}",
      "email_from_address" => "example@127.0.0.1",
    }, user.registration_input_options)
  end

  def test_registration_options_below_length_limit
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :user => FactoryBot.attributes_for(:api_user),
        :options => {
          :foo => "a" * 3900,
        },
      }),
    }))
    assert_response_code(201, response)

    data = MultiJson.load(response.body)
    user = ApiUser.find(data["user"]["id"])
    assert_equal({
      "foo" => "a" * 3900,
      "site_name" => "API Umbrella",
    }, user.registration_options)
    assert_equal({
      "foo" => "a" * 3900,
    }, user.registration_input_options)
  end

  def test_registration_options_too_long
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump({
        :user => FactoryBot.attributes_for(:api_user),
        :options => {
          :foo => "a" * 4000,
        },
      }),
    }))
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [
        {
          "code" => "INVALID_INPUT",
          "field" => "registration_options",
          "message" => "is too long",
          "full_message" => "Registration options: is too long",
        },
        {
          "code" => "INVALID_INPUT",
          "field" => "registration_input_options",
          "message" => "is too long",
          "full_message" => "Registration input options: is too long",
        },
      ],
    }, data)
  end

  private

  def non_admin_key_creator_api_key
    @non_admin_key_creator_api_user = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    })

    { :headers => { "X-Api-Key" => @non_admin_key_creator_api_user.api_key } }
  end

  def active_count
    ApiUser.count
  end

  def make_request(options = {})
    attributes = FactoryBot.attributes_for(:api_user, options)
    Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/json" },
      :body => MultiJson.dump(:user => attributes),
    }))
  end
end

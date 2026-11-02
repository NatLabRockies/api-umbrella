require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestRequestDeactivation < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::SentEmails

  def setup
    super
    setup_server

    clear_all_test_emails
  end

  def test_valid_create
    api_user = FactoryBot.create(:api_user)
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    response = make_request(api_key: api_user.api_key, email: api_user.email)
    assert_response_code(201, response)

    # ap api_user
    api_user.reload
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)

    assert_equal(1, sent_emails.fetch("total"))
    # ap sent_email_contents

    # data = MultiJson.load(response.body)
    # assert_equal(attributes[:last_name], data["user"]["last_name"])

    # user = ApiUser.find(data["user"]["id"])
    # assert_equal(attributes[:last_name], user.last_name)

    # assert_equal(1, active_count - initial_count)
  end

  def test_api_key_not_found
    api_user = FactoryBot.create(:api_user)
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    response = make_request(api_key: api_user.api_key.swapcase, email: api_user.email)
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "email",
        "message" => "a matching email and API key could not be found",
        "full_message" => "Email: a matching email and API key could not be found",
      }],
    }, data)

    api_user.reload
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    assert_equal(0, sent_emails.fetch("total"))
  end

  def test_email_not_found
    api_user = FactoryBot.create(:api_user)
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    response = make_request(api_key: api_user.api_key, email: "foo#{api_user.email}")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "email",
        "message" => "a matching email and API key could not be found",
        "full_message" => "Email: a matching email and API key could not be found",
      }],
    }, data)

    api_user.reload
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    assert_equal(0, sent_emails.fetch("total"))
  end

  def test_invalid_api_key_format
    response = make_request(api_key: nil, email: "foo@example.com")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "api_key",
        "message" => "is too short (minimum is 40 characters)",
        "full_message" => "API Key: is too short (minimum is 40 characters)",
      }],
    }, data)

    response = make_request(api_key: "", email: "foo@example.com")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "api_key",
        "message" => "is too short (minimum is 40 characters)",
        "full_message" => "API Key: is too short (minimum is 40 characters)",
      }],
    }, data)

    response = make_request(api_key: "invalidkey", email: "foo@example.com")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "api_key",
        "message" => "is too short (minimum is 40 characters)",
        "full_message" => "API Key: is too short (minimum is 40 characters)",
      }],
    }, data)

    response = make_request(api_key: "a" * 41, email: "foo@example.com")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "api_key",
        "message" => "is too long (maximum is 40 characters)",
        "full_message" => "API Key: is too long (maximum is 40 characters)",
      }],
    }, data)
  end

  def test_invalid_email_length
    response = make_request(api_key: "a" * 40, email: nil)
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "email",
        "message" => "can't be blank",
        "full_message" => "Email: can't be blank",
      }],
    }, data)

    response = make_request(api_key: "a" * 40, email: "")
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "email",
        "message" => "can't be blank",
        "full_message" => "Email: can't be blank",
      }],
    }, data)

    response = make_request(api_key: "a" * 40, email: "#{"a" * 250}@a.com")
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

  def test_invalid_email_format
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
      response = make_request(api_key: "a" * 40, email: bad)
      assert_response_code(422, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "errors" => [{
          "code" => "INVALID_INPUT",
          "field" => "email",
          "message" => "is invalid",
          "full_message" => "Email: is invalid",
        }],
      }, data)
    end
  end

  private

  def non_admin_auth
    @non_admin_key_creator_api_user ||= FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    })

    { :headers => { "X-Api-Key" => @non_admin_key_creator_api_user.api_key } }
  end

  def make_request(attributes)
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users/request-deactivation.json", http_options.deep_merge(non_admin_auth).deep_merge({
      headers: { "Content-Type" => "application/json" },
      body: MultiJson.dump(user: attributes)
    }))
  end
end

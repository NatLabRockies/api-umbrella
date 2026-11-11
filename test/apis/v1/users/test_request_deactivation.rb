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

    response = make_request(user: { api_key: api_user.api_key, email: api_user.email })
    assert_response_code(201, response)

    api_user.reload
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)

    data = MultiJson.load(response.body)
    assert_equal({
      "user" => {
        "deactivation_sent_at" => api_user.deactivation_sent_at.utc.iso8601,
        "api_key_suffix" => api_user.api_key_suffix,
        "email" => api_user.email,
      },
    }, data)
    assert_equal(6, data.fetch("user").fetch("api_key_suffix").length)

    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))
    message = messages.fetch("messages").first

    assert_equal("", message.fetch("HTML"))
    assert_match("deactivate your API key ending in \"#{api_user.api_key_suffix}\".", message.fetch("Text"))
    refute_match(api_user.deactivation_token_hash, message.fetch("Text"))

    url_matcher = %r{^https://127.0.0.1:9081/signup/#/confirm-deactivation\?token=(\w+)$}
    assert_match(url_matcher, message.fetch("Text"))

    token = message.fetch("Text").match(url_matcher)[1]
    assert(token)
    assert_equal(30, token.length)
    assert_match(/\A[6789BCDFGHJKLMNPQRTWbcdfghjkmnpqrtwz]+\z/, token)

    assert_equal(OpenSSL::HMAC.hexdigest("sha256", $config["secret_key"], token), api_user.deactivation_token_hash)

    assert_equal("Confirm 127.0.0.1 API key deactivation request", message.fetch("Subject"))
    assert_equal("noreply@127.0.0.1", message.fetch("From").fetch("Address"))
    assert_equal("127.0.0.1 Keys", message.fetch("From").fetch("Name"))
  end

  def test_api_key_not_found
    api_user = FactoryBot.create(:api_user)
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    response = make_request(user: { api_key: api_user.api_key.swapcase, email: api_user.email })
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

    response = make_request(user: { api_key: api_user.api_key, email: "foo#{api_user.email}" })
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

  def test_matches_email_case_insensitively
    api_user = FactoryBot.create(:api_user)

    response = make_request(user: { api_key: api_user.api_key, email: api_user.email.swapcase })
    assert_response_code(201, response)
  end

  def test_invalid_api_key_format
    response = make_request(user: { api_key: nil, email: "foo@example.com" })
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

    response = make_request(user: { api_key: "", email: "foo@example.com" })
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

    response = make_request(user: { api_key: "invalidkey", email: "foo@example.com" })
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

    response = make_request(user: { api_key: "a" * 41, email: "foo@example.com" })
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
    response = make_request(user: { api_key: "a" * 40, email: nil })
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

    response = make_request(user: { api_key: "a" * 40, email: "" })
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

    response = make_request(user: { api_key: "a" * 40, email: "#{"a" * 250}@a.com" })
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
      response = make_request(user: { api_key: "a" * 40, email: bad })
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

  def test_api_key_already_disabled
    api_user = FactoryBot.create(:api_user, disabled_at: Time.now)
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    response = make_request(user: { api_key: api_user.api_key, email: api_user.email })
    assert_response_code(422, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "errors" => [{
        "code" => "INVALID_INPUT",
        "field" => "api_key",
        "message" => "is already deactivated",
        "full_message" => "API Key: is already deactivated",
      }],
    }, data)

    api_user.reload
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)

    assert_equal(0, sent_emails.fetch("total"))
  end

  def test_replaces_existing_token
    api_user = FactoryBot.create(:api_user, deactivation_token_hash: OpenSSL::HMAC.hexdigest("sha256", $config["secret_key"], "example"), deactivation_sent_at: Time.now - 60)
    original_deactivation_token_hash = api_user.deactivation_token_hash
    original_deactivation_sent_at = api_user.deactivation_sent_at
    assert(original_deactivation_token_hash)
    assert(original_deactivation_sent_at)

    response = make_request(user: { api_key: api_user.api_key, email: api_user.email })
    assert_response_code(201, response)
    assert_equal(1, sent_emails.fetch("total"))

    api_user.reload
    refute_equal(api_user.deactivation_token_hash, original_deactivation_token_hash)
    refute_equal(api_user.deactivation_sent_at, original_deactivation_sent_at)
  end

  def test_uses_submitted_from_url_if_allowed
    prepend_website_backends([
      {
        :frontend_host => unique_test_hostname,
        :backend_protocol => "http",
        :server_host => "127.0.0.1",
        :server_port => 9443,
      },
    ]) do
      api_user = FactoryBot.create(:api_user)

      response = make_request(user: { api_key: api_user.api_key, email: api_user.email }, options: { submitted_from_url: "https://#{unique_test_hostname}/other-signup?foo=bar#baz" })
      assert_response_code(201, response)

      message = sent_email_contents.fetch("messages").first
      refute_match("https://127.0.0.1:9081", message.fetch("Text"))
      assert_match("https://#{unique_test_hostname}/other-signup?foo=bar#/confirm-deactivation?token=", message.fetch("Text"))

      assert_equal("Confirm #{unique_test_hostname} API key deactivation request", message.fetch("Subject"))
      assert_equal("noreply@127.0.0.1", message.fetch("From").fetch("Address"))
      assert_equal("#{unique_test_hostname} Keys", message.fetch("From").fetch("Name"))
    end
  end

  def test_uses_default_url_if_submitted_from_url_is_disallowed
    api_user = FactoryBot.create(:api_user)

    response = make_request(user: { api_key: api_user.api_key, email: api_user.email }, options: { submitted_from_url: "https://#{unique_test_hostname}/other-signup?foo=bar#baz" })
    assert_response_code(201, response)

    message = sent_email_contents.fetch("messages").first
    refute_match(unique_test_hostname, message.fetch("Text"))
    assert_match("https://127.0.0.1:9081", message.fetch("Text"))

    assert_equal("Confirm 127.0.0.1 API key deactivation request", message.fetch("Subject"))
    assert_equal("noreply@127.0.0.1", message.fetch("From").fetch("Address"))
    assert_equal("127.0.0.1 Keys", message.fetch("From").fetch("Name"))
  end

  def test_default_url_does_not_use_header_hosts
    api_user = FactoryBot.create(:api_user)

    response = make_request(user: { api_key: api_user.api_key, email: api_user.email }, headers: { "Host" => unique_test_hostname, "X-Forwarded-Host" => unique_test_hostname })
    assert_response_code(201, response)

    message = sent_email_contents.fetch("messages").first
    refute_match(unique_test_hostname, message.fetch("Text"))
    assert_match("https://127.0.0.1:9081", message.fetch("Text"))

    assert_equal("Confirm 127.0.0.1 API key deactivation request", message.fetch("Subject"))
    assert_equal("noreply@127.0.0.1", message.fetch("From").fetch("Address"))
    assert_equal("127.0.0.1 Keys", message.fetch("From").fetch("Name"))
  end

  private

  def non_admin_auth
    @non_admin_key_creator_api_user ||= FactoryBot.create(:api_user, {
      roles: ["api-umbrella-key-creator"],
    })

    { headers: { "X-Api-Key" => @non_admin_key_creator_api_user.api_key } }
  end

  def make_request(user:, options: {}, headers: {})
    data = { user: user }
    if options.present?
      data.merge!(options: options)
    end
    Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users/request-deactivation.json", http_options.deep_merge(non_admin_auth).deep_merge({
      headers: { "Content-Type" => "application/json" }.merge(headers),
      body: MultiJson.dump(data),
    }))
  end
end

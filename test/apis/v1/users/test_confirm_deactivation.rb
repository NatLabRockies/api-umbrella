require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestConfirmDeactivation < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_valid_show
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)
    refute(api_user.disabled_at)

    response = make_request(user: { deactivation_token: api_user.deactivation_token })
    assert_response_code(200, response)

    api_user.reload
    refute(api_user.deactivation_token_hash)
    refute(api_user.deactivation_sent_at)
    assert(api_user.disabled_at)

    data = MultiJson.load(response.body)
    assert_equal({
      "user" => {
        "api_key_suffix" => api_user.api_key_suffix,
        "created_at" => api_user.created_at.utc.iso8601,
      },
    }, data)
    assert_equal(6, data.fetch("user").fetch("api_key_suffix").length)
  end

  def test_invalid_token
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)

    response = make_request(user: { deactivation_token: api_user.deactivation_token.swapcase })
    assert_response_code(404, response)
  end

  def test_under_expired_time
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now - 5.hours - 50.minutes)
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)

    response = make_request(user: { deactivation_token: api_user.deactivation_token })
    assert_response_code(200, response)
  end

  def test_expired_token
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now - 6.hours - 10.minutes)
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)

    response = make_request(user: { deactivation_token: api_user.deactivation_token })
    assert_response_code(404, response)
  end

  def test_wildcard_cors
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)

    response = make_request(user: { deactivation_token: api_user.deactivation_token })
    assert_response_code(200, response)
    assert_equal("*", response.headers["Access-Control-Allow-Origin"])

    response = make_request(user: { deactivation_token: "foo" })
    assert_response_code(404, response)
    assert_equal("*", response.headers["Access-Control-Allow-Origin"])
  end

  def test_cors_preflight
    response = Typhoeus.options("https://127.0.0.1:9081/api-umbrella/v1/users/confirm-deactivation.json", keyless_http_options)
    assert_response_code(204, response)
    assert_equal("Content-Type, X-Api-Key", response.headers["Access-Control-Allow-Headers"])
    assert_equal("POST, OPTIONS", response.headers["Access-Control-Allow-Methods"])
    assert_equal("*", response.headers["Access-Control-Allow-Origin"])
    assert_equal("600", response.headers["Access-Control-Max-Age"])
  end

  private

  def non_admin_auth
    @non_admin_key_creator_api_user ||= FactoryBot.create(:api_user, {
      roles: ["api-umbrella-key-creator"],
    })

    { headers: { "X-Api-Key" => @non_admin_key_creator_api_user.api_key } }
  end

  def make_request(user:)
    data = { user: user }
    Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users/confirm-deactivation.json", http_options.deep_merge(non_admin_auth).deep_merge({
      headers: { "Content-Type" => "application/json" },
      body: MultiJson.dump(data),
    }))
  end
end

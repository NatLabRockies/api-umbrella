require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestShowConfirmDeactivation < Minitest::Test
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

    response = make_request(token: api_user.deactivation_token)
    assert_response_code(200, response)

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

    response = make_request(token: api_user.deactivation_token.swapcase)
    assert_response_code(404, response)
  end

  def test_under_expired_time
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now - 5.hours - 50.minutes)
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)

    response = make_request(token: api_user.deactivation_token)
    assert_response_code(200, response)
  end

  def test_expired_token
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now - 6.hours - 10.minutes)
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)

    response = make_request(token: api_user.deactivation_token)
    assert_response_code(404, response)
  end

  def test_wildcard_cors
    api_user = FactoryBot.create(:api_user, deactivation_token: SecureRandom.alphanumeric(30), deactivation_sent_at: Time.now)

    response = make_request(token: api_user.deactivation_token)
    assert_response_code(200, response)
    assert_equal("*", response.headers["Access-Control-Allow-Origin"])

    response = make_request(token: "foo")
    assert_response_code(404, response)
    assert_equal("*", response.headers["Access-Control-Allow-Origin"])
  end

  private

  def non_admin_auth
    @non_admin_key_creator_api_user ||= FactoryBot.create(:api_user, {
      roles: ["api-umbrella-key-creator"],
    })

    { headers: { "X-Api-Key" => @non_admin_key_creator_api_user.api_key } }
  end

  def make_request(attributes)
    Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/users/confirm-deactivation.json", http_options.deep_merge(non_admin_auth).deep_merge({
      params: attributes,
    }))
  end
end

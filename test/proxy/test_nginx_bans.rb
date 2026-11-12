require_relative "../test_helper"

class Test::Proxy::TestNginxBans < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_bans_user_agent_case_insensitive
    override_config({
      "ban" => {
        "user_agents" => ["~*naughty"],
      },
    }) do
      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
      assert_response_code(200, response)

      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options.deep_merge({
        :headers => {
          "User-Agent" => "some NaUghtY user_agent",
        },
      }))
      assert_response_code(403, response)
    end
  end

  def test_bans_individual_ips_and_cidr_ranges
    override_config({
      "ban" => {
        "ips" => ["7.4.2.2", "8.7.1.0/24"],
      },
    }) do
      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
      assert_response_code(200, response)

      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options.deep_merge({
        :headers => {
          "X-Forwarded-For" => "7.4.2.2",
        },
      }))
      assert_response_code(403, response)

      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options.deep_merge({
        :headers => {
          "X-Forwarded-For" => "8.7.1.44",
        },
      }))
      assert_response_code(403, response)
    end
  end

  def test_ban_response_customization
    # Test defaults.
    override_config({
      "ban" => {
        "user_agents" => ["~*naughty"],
      },
    }) do
      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
      assert_response_code(200, response)

      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options.deep_merge({
        :headers => {
          "User-Agent" => "naughty",
        },
      }))
      assert_response_code(403, response)
      assert_operator(response.total_time, :<, 0.5)
      assert_equal("Please contact us for assistance.\n", response.body)
    end

    # Test customizations.
    override_config({
      "ban" => {
        "user_agents" => ["~*naughty"],
        "response" => {
          "status_code" => 418,
          "delay" => 1,
          "message" => "You've been banned!",
        },
      },
    }) do
      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options)
      assert_response_code(200, response)

      response = Typhoeus.get("http://127.0.0.1:9080/api/info/", http_options.deep_merge({
        :headers => {
          "User-Agent" => "naughty",
        },
      }))
      assert_response_code(418, response)
      assert_operator(response.total_time, :>, 0.7)
      assert_operator(response.total_time, :<, 1.3)
      assert_equal("You've been banned!\n", response.body)
    end
  end

  def test_bans_from_non_api_web_site
    override_config({
      "ban" => {
        "user_agents" => ["~*naughty"],
      },
    }) do
      response = Typhoeus.get("https://127.0.0.1:9081/signup/", http_options)
      assert_response_code(200, response)
      assert_match("API Key Sign Up", response.body)

      response = Typhoeus.get("https://127.0.0.1:9081/signup/", http_options.deep_merge({
        :headers => {
          "User-Agent" => "naughty",
        },
      }))
      assert_response_code(403, response)
    end
  end
end

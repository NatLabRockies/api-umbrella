require_relative "../test_helper"

class Test::Proxy::TestNginxRobotsTxt < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup

  EXAMPLE_ROBOTS_TXT = "User-agent: *\nDisallow: /\n".freeze

  def setup
    super
    setup_server
  end

  def test_default_host
    override_config({
      "hosts" => [
        {
          "hostname" => "default.foo",
          "default" => true,
          "robots_txt" => EXAMPLE_ROBOTS_TXT,
        },
        {
          "hostname" => "known.foo",
        },
      ],
    }) do
      # Known host with robots.txt
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "default.foo" },
      }))
      assert_response_code(200, response)
      assert_equal(EXAMPLE_ROBOTS_TXT, response.body)

      # Known host without robots.txt
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "known.foo" },
      }))
      assert_response_code(404, response)

      # Unknown host
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "unknown.foo" },
      }))
      assert_response_code(200, response)
      assert_equal(EXAMPLE_ROBOTS_TXT, response.body)
    end
  end

  def test_no_default_host
    override_config({
      "hosts" => [
        {
          "hostname" => "default.foo",
          "robots_txt" => EXAMPLE_ROBOTS_TXT,
        },
      ],
    }) do
      # Known host with robots.txt
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "default.foo" },
      }))
      assert_response_code(200, response)
      assert_equal(EXAMPLE_ROBOTS_TXT, response.body)

      # Unknown host
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "unknown.foo" },
      }))
      assert_response_code(404, response)
    end
  end

  # When nginx has no default_server defined, then the first server defined
  # becomes the default one. So test to see how this ordering also interacts
  # with a wildcard host.
  def test_no_default_host_wildcard_first
    override_config({
      "hosts" => [
        {
          "hostname" => "*",
          "robots_txt" => EXAMPLE_ROBOTS_TXT,
        },
        {
          "hostname" => "known.foo",
        },
      ],
    }) do
      # Known host without robots.txt
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "known.foo" },
      }))
      assert_response_code(404, response)

      # Unknown host
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "unknown.foo" },
      }))
      assert_response_code(404, response)
    end
  end

  def test_no_default_host_wildcard_last
    override_config({
      "hosts" => [
        {
          "hostname" => "known.foo",
        },
        {
          "hostname" => "*",
          "robots_txt" => EXAMPLE_ROBOTS_TXT,
        },
      ],
    }) do
      # Known host without robots.txt
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "known.foo" },
      }))
      assert_response_code(404, response)

      # Unknown host
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "unknown.foo" },
      }))
      assert_response_code(404, response)
    end
  end

  def test_wildcard_is_default
    override_config({
      "hosts" => [
        {
          "hostname" => "*",
          "default" => true,
          "robots_txt" => EXAMPLE_ROBOTS_TXT,
        },
        {
          "hostname" => "known.foo",
        },
      ],
    }) do
      # Known host without robots.txt
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "known.foo" },
      }))
      assert_response_code(404, response)

      # Unknown host
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "unknown.foo" },
      }))
      assert_response_code(200, response)
      assert_equal(EXAMPLE_ROBOTS_TXT, response.body)
    end
  end

  def test_wildcard_is_not_default
    override_config({
      "hosts" => [
        {
          "hostname" => "*",
          "robots_txt" => EXAMPLE_ROBOTS_TXT,
        },
        {
          "hostname" => "known.foo",
          "default" => true,
        },
      ],
    }) do
      # Known host without robots.txt
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "known.foo" },
      }))
      assert_response_code(404, response)

      # Unknown host
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_options.deep_merge({
        :headers => { "Host" => "unknown.foo" },
      }))
      assert_response_code(404, response)
    end
  end

  def test_precedence
    override_config({
      "apis" => [
        {
          "frontend_host" => "with-apis-and-website.foo",
          "backend_host" => "127.0.0.1",
          "servers" => [{ "host" => "127.0.0.1", "port" => 9444 }],
          "url_matches" => [{ "frontend_prefix" => "/#{unique_test_id}/api-example/", "backend_prefix" => "/hello/" }],
        },
      ],
      "website_backends" => [
        {
          "frontend_host" => "with-apis-and-website.foo",
          "server_host" => "127.0.0.1",
          "server_port" => 9444,
        },
      ],
      "hosts" => [
        {
          "hostname" => "with-apis-and-website.foo",
          "default" => true,
          "robots_txt" => EXAMPLE_ROBOTS_TXT,
        },
      ],
    }) do
      http_opts = http_options.deep_merge({
        :headers => { "Host" => "with-apis-and-website.foo" },
      })

      # robots.txt match before API Backends, Website Backends, and anything else.
      response = Typhoeus.get("https://127.0.0.1:9081/robots.txt", http_opts)
      assert_response_code(200, response)
      assert_equal(EXAMPLE_ROBOTS_TXT, response.body)
    end
  end
end

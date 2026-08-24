require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestCreateWelcomeEmailSanitizedLinks < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::SentEmails

  def setup
    super
    setup_server
  end

  def test_rejects_links_to_unknown_hosts
    refute_host_links(unique_test_hostname)
  end

  def test_allows_links_to_api_backend_hosts
    prepend_api_backends([
      {
        :frontend_host => unique_test_hostname,
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      assert_host_links(unique_test_hostname)
    end
  end

  def test_allows_contact_links_to_website_backend_hosts
    prepend_website_backends([
      {
        :frontend_host => unique_test_hostname,
        :backend_protocol => "http",
        :server_host => "127.0.0.1",
        :server_port => 9443,
      },
    ]) do
      assert_contact_only_host_links(unique_test_hostname)
    end
  end

  def test_allows_contact_links_to_subdomains
    prepend_api_backends([
      {
        :frontend_host => unique_test_hostname,
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      assert_contact_only_host_links("www.#{unique_test_hostname}")
    end
  end

  def test_allows_contact_links_to_parent_domains
    prepend_api_backends([
      {
        :frontend_host => "api.#{unique_test_hostname}",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      assert_contact_only_host_links(unique_test_hostname)
    end
  end

  def test_allows_contact_links_to_sibling_subdomain
    prepend_api_backends([
      {
        :frontend_host => "api.#{unique_test_hostname}",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      assert_contact_only_host_links("www.#{unique_test_hostname}")
    end
  end

  def test_allows_links_to_public_suffix_domain
    prepend_api_backends([
      {
        :frontend_host => "#{unique_test_subdomain}.cloudfront.net",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      assert_host_links("#{unique_test_subdomain}.cloudfront.net")
    end
  end

  def test_rejects_links_to_sibling_public_suffix_domain
    prepend_api_backends([
      {
        :frontend_host => "#{unique_test_subdomain}.cloudfront.net",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      refute_host_links("unknown.cloudfront.net")
    end
  end

  def test_file_config_hosts
    override_config({
      "hosts" => [
        {
          "hostname" => unique_test_hostname,
        },
      ],
      "nginx" => {
        "server_names_hash_bucket_size" => 128,
      },
    }) do
      assert_host_links(unique_test_hostname)
    end
  end

  def test_file_config_api_backends
    override_config({
      "apis" => [
        {
          "frontend_host" => unique_test_hostname,
          "backend_host" => "127.0.0.1",
          "servers" => [{ "host" => "127.0.0.1", "port" => 9444 }],
          "url_matches" => [{ "frontend_prefix" => "/#{unique_test_id}/", "backend_prefix" => "/" }],
        },
      ],
    }) do
      assert_host_links(unique_test_hostname)
    end
  end

  def test_file_config_website_backends
    override_config({
      "website_backends" => [
        {
          "frontend_host" => unique_test_hostname,
          "server_host" => "127.0.0.1",
          "server_port" => 9443,
        },
      ],
    }) do
      assert_contact_only_host_links(unique_test_hostname)
    end
  end

  def test_file_config_web_default_host
    override_config({
      "web" => {
        "default_host" => unique_test_hostname,
      },
    }) do
      assert_host_links(unique_test_hostname)
    end
  end

  def test_explicit_allowed_url_config
    refute_host_links("github.com")
    refute_host_links("test.example.com")

    override_config({
      "web" => {
        "allowed_signup_embed_urls_regex" => "^(https://github\\.com/nrel/|https://test.example\\.com/foo/|mailto:foo@test.example\\.com|bar@test.example\\.com)",
      },
    }) do
      refute_host_links("github.com")
      refute_host_links("test.example.com")

      message = create_user({
        :contact_url => "https://github.com/github/example/issues",
      })
      refute_match("github.com", message.fetch("Text"))

      message = create_user({
        :contact_url => "https://foo.example.com/foo/bar/",
      })
      refute_match("foo.example.com", message.fetch("Text"))

      message = create_user({
        :email_from_address => "bar@test.example.com",
        :contact_url => "https://github.com/NREL/api-umbrella/issues",
      })
      assert_equal(["bar@test.example.com"], message.fetch("headers").fetch("From"))
      assert_match("https://github.com/NREL/api-umbrella/issues", message.fetch("Text"))

      message = create_user({
        :contact_url => "https://test.example.com/foo/bar/",
      })
      assert_match("https://test.example.com/foo/bar/", message.fetch("Text"))

      message = create_user({
        :contact_url => "mailto:foo@test.example.com",
      })
      assert_match(/(?!mailto:)foo@test\.example\.com/, message.fetch("Text"))
      assert_match("mailto:foo@test.example.com", message.fetch("HTML"))
    end
  end

  def test_prepends_missing_mailto_on_contact_url_response
    prepend_api_backends([
      {
        :frontend_host => unique_test_hostname,
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
        :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
        :body => {
          :user => FactoryBot.attributes_for(:api_user),
          :options => {
            :send_welcome_email => true,
            :contact_url => "example@#{unique_test_hostname}",
          },
        },
      }))
      assert_response_code(201, response)

      data = MultiJson.load(response.body)
      assert_equal("mailto:example@#{unique_test_hostname}", data.fetch("options").fetch("contact_url"))
    end
  end

  private

  def create_user(options = {})
    clear_all_test_emails

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
        :options => {
          :send_welcome_email => true,
        }.deep_merge(options),
      },
    }))
    assert_response_code(201, response)

    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))
    messages.fetch("messages").first
  end

  def assert_host_links(host)
    message = create_user({
      :email_from_address => "test@#{host}",
      :example_api_url => "https://#{host}/api.json?test=1",
      :contact_url => "https://#{host}/contact-us",
    })

    assert_equal(["test@#{host}"], message.fetch("headers").fetch("From"))
    refute_match("https://#{host}/api.json?test=1", message.fetch("Text"))
    assert_match("please contact us ( https://#{host}/contact-us ).", message.fetch("Text"))

    message = create_user({
      :contact_url => "mailto:example@#{host}",
    })
    assert_match("please contact us ( example@#{host} )", message.fetch("Text"))
    assert_match(%(please <a href="mailto:example@#{host}">contact us</a>.), message.fetch("HTML"))

    message = create_user({
      :contact_url => "example@#{host}",
    })
    assert_match("please contact us ( example@#{host} )", message.fetch("Text"))
    assert_match(%(please <a href="mailto:example@#{host}">contact us</a>.), message.fetch("HTML"))
  end

  def refute_host_links(host)
    message = create_user({
      :email_from_address => "test@#{host}",
      :example_api_url => "https://#{host}/api.json?test=1",
      :contact_url => "https://#{host}/contact-us",
    })

    assert_equal(["noreply@localhost"], message.fetch("headers").fetch("From"))
    refute_match(host, message.fetch("Text"))
    refute_match(host, message.fetch("HTML"))
    assert_match("please contact us.", message.fetch("Text"))

    message = create_user({
      :contact_url => "mailto:example@#{host}",
    })
    assert_match("please contact us.", message.fetch("Text"))
    assert_match("please contact us.", message.fetch("HTML"))

    message = create_user({
      :contact_url => "example@#{host}",
    })
    assert_match("please contact us.", message.fetch("Text"))
    assert_match("please contact us.", message.fetch("HTML"))
  end

  def assert_contact_only_host_links(host)
    message = create_user({
      :email_from_address => "test@#{host}",
      :example_api_url => "https://#{host}/api.json?test=1",
      :contact_url => "https://#{host}/contact-us",
    })

    assert_equal(["test@#{host}"], message.fetch("headers").fetch("From"))
    refute_match("api.json", message.fetch("Text"))
    assert_match("please contact us ( https://#{host}/contact-us ).", message.fetch("Text"))

    message = create_user({
      :contact_url => "mailto:example@#{host}",
    })
    assert_match("please contact us ( example@#{host} )", message.fetch("Text"))
    assert_match(%(please <a href="mailto:example@#{host}">contact us</a>.), message.fetch("HTML"))

    message = create_user({
      :contact_url => "example@#{host}",
    })
    assert_match("please contact us ( example@#{host} )", message.fetch("Text"))
    assert_match(%(please <a href="mailto:example@#{host}">contact us</a>.), message.fetch("HTML"))
  end
end

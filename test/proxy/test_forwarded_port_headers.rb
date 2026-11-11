require_relative "../test_helper"

class Test::Proxy::TestForwardedPortHeaders < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup
  include Minitest::Hooks

  def setup
    super
    setup_server

    @default_config = {
      :web => {
        :admin => {
          :auth_strategies => {
            :enabled => ["google"],
          },
        },
      },
    }

    once_per_class_setup do
      FactoryBot.create(:admin)
      override_config_set(@default_config)
      prepend_api_backends([
        {
          :frontend_host => "frontend.foo",
          :backend_host => "example.com",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/front/end/path", :backend_prefix => "/backend-prefix" }],
        },
      ])
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_default_headers
    headers = {}
    responses = make_requests(headers)
    responses.each do |type, response|
      case(type)
      when :admin_https
        assert_response_code(200, response)
      when :admin_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admin/login", response.headers["Location"])
      when :admin_oauth2_https
        assert_response_code(302, response)
        assert_oauth2_redirect_uri("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", response)
      when :admin_oauth2_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admins/auth/google_oauth2", response.headers["Location"])
      when :api_backend_redirect_http
        assert_response_code(302, response)
        assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
      when :api_backend_redirect_https
        assert_response_code(302, response)
        assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
      when :website_https
        assert_response_code(200, response)
      when :website_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/", response.headers["Location"])
      when :website_signup_https
        assert_response_code(200, response)
      when :website_signup_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/signup/", response.headers["Location"])
      else
        raise "Unhandled type: #{type}"
      end
    end
  end

  def test_forwarded_port
    headers = { "X-Forwarded-Port" => "1111" }
    responses = make_requests(headers)
    responses.each do |type, response|
      case(type)
      when :admin_https
        assert_response_code(200, response)
      when :admin_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admin/login", response.headers["Location"])
      when :admin_oauth2_https
        assert_response_code(302, response)
        assert_oauth2_redirect_uri("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", response)
      when :admin_oauth2_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admins/auth/google_oauth2", response.headers["Location"])
      when :api_backend_redirect_http
        assert_response_code(302, response)
        assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
      when :api_backend_redirect_https
        assert_response_code(302, response)
        assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
      when :website_https
        assert_response_code(200, response)
      when :website_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/", response.headers["Location"])
      when :website_signup_https
        assert_response_code(200, response)
      when :website_signup_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/signup/", response.headers["Location"])
      else
        raise "Unhandled type: #{type}"
      end
    end
  end

  def test_forwarded_proto_http
    headers = { "X-Forwarded-Proto" => "http" }
    responses = make_requests(headers)
    responses.each do |type, response|
      case(type)
      when :admin_https, :admin_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admin/login", response.headers["Location"])
      when :admin_oauth2_https, :admin_oauth2_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admins/auth/google_oauth2", response.headers["Location"])
      when :api_backend_redirect_http
        assert_response_code(302, response)
        assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
      when :api_backend_redirect_https
        assert_response_code(302, response)
        assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
      when :website_https, :website_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/", response.headers["Location"])
      when :website_signup_https, :website_signup_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/signup/", response.headers["Location"])
      else
        raise "Unhandled type: #{type}"
      end
    end
  end

  def test_forwarded_proto_https
    headers = { "X-Forwarded-Proto" => "https" }
    responses = make_requests(headers)
    responses.each do |type, response|
      case(type)
      when :admin_https, :admin_http
        assert_response_code(200, response)
      when :admin_oauth2_https, :admin_oauth2_http
        assert_response_code(302, response)
        assert_oauth2_redirect_uri("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", response)
      when :api_backend_redirect_http
        assert_response_code(302, response)
        assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
      when :api_backend_redirect_https
        assert_response_code(302, response)
        assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
      when :website_https, :website_http
        assert_response_code(200, response)
      when :website_signup_https, :website_signup_http
        assert_response_code(200, response)
      else
        raise "Unhandled type: #{type}"
      end
    end
  end

  def test_forwarded_proto_http_and_port
    headers = { "X-Forwarded-Proto" => "http", "X-Forwarded-Port" => "1111" }
    responses = make_requests(headers)
    responses.each do |type, response|
      case(type)
      when :admin_https, :admin_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admin/login", response.headers["Location"])
      when :admin_oauth2_https, :admin_oauth2_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/admins/auth/google_oauth2", response.headers["Location"])
      when :api_backend_redirect_http
        assert_response_code(302, response)
        assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
      when :api_backend_redirect_https
        assert_response_code(302, response)
        assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
      when :website_https, :website_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/", response.headers["Location"])
      when :website_signup_https, :website_signup_http
        assert_response_code(301, response)
        assert_equal("https://127.0.0.1:9081/signup/", response.headers["Location"])
      else
        raise "Unhandled type: #{type}"
      end
    end
  end

  def test_forwarded_proto_https_and_port
    headers = { "X-Forwarded-Proto" => "https", "X-Forwarded-Port" => "1111" }
    responses = make_requests(headers)
    responses.each do |type, response|
      case(type)
      when :admin_https, :admin_http
        assert_response_code(200, response)
      when :admin_oauth2_https, :admin_oauth2_http
        assert_response_code(302, response)
        assert_oauth2_redirect_uri("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", response)
      when :api_backend_redirect_http
        assert_response_code(302, response)
        assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
      when :api_backend_redirect_https
        assert_response_code(302, response)
        assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
      when :website_https, :website_http
        assert_response_code(200, response)
      when :website_signup_https, :website_signup_http
        assert_response_code(200, response)
      else
        raise "Unhandled type: #{type}"
      end
    end
  end

  def test_override_public_http_port
    override_config(@default_config.deep_merge({
      :override_public_http_port => 2222,
    })) do
      headers = { "X-Forwarded-Port" => "1111" }
      responses = make_requests(headers)
      responses.each do |type, response|
        case(type)
        when :admin_https
          assert_response_code(200, response)
        when :admin_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/admin/login", response.headers["Location"])
        when :admin_oauth2_https
          assert_response_code(302, response)
          assert_oauth2_redirect_uri("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", response)
        when :admin_oauth2_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/admins/auth/google_oauth2", response.headers["Location"])
        when :api_backend_redirect_http
          assert_response_code(302, response)
          assert_equal("http://frontend.foo:2222/hello?api_key=#{api_key}", response.headers["Location"])
        when :api_backend_redirect_https
          assert_response_code(302, response)
          assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
        when :website_https
          assert_response_code(200, response)
        when :website_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/", response.headers["Location"])
        when :website_signup_https
          assert_response_code(200, response)
        when :website_signup_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/signup/", response.headers["Location"])
        else
          raise "Unhandled type: #{type}"
        end
      end
    end
  end

  def test_override_public_https_port
    override_config(@default_config.deep_merge({
      :override_public_https_port => 3333,
    })) do
      headers = { "X-Forwarded-Port" => "1111" }
      responses = make_requests(headers)
      responses.each do |type, response|
        case(type)
        when :admin_https
          assert_response_code(200, response)
        when :admin_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:3333/admin/login", response.headers["Location"])
        when :admin_oauth2_https
          assert_response_code(302, response)
          assert_oauth2_redirect_uri("https://127.0.0.1:3333/admins/auth/google_oauth2/callback", response)
        when :admin_oauth2_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:3333/admins/auth/google_oauth2", response.headers["Location"])
        when :api_backend_redirect_http
          assert_response_code(302, response)
          assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
        when :api_backend_redirect_https
          assert_response_code(302, response)
          assert_equal("https://frontend.foo:3333/hello?api_key=#{api_key}", response.headers["Location"])
        when :website_https
          assert_response_code(200, response)
        when :website_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:3333/", response.headers["Location"])
        when :website_signup_https
          assert_response_code(200, response)
        when :website_signup_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:3333/signup/", response.headers["Location"])
        else
          raise "Unhandled type: #{type}"
        end
      end
    end
  end

  def test_override_public_http_proto
    override_config(@default_config.deep_merge({
      :override_public_http_proto => "https",
    })) do
      headers = { "X-Forwarded-Proto" => "http" }
      responses = make_requests(headers)
      responses.each do |type, response|
        case(type)
        when :admin_https
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/admin/login", response.headers["Location"])
        when :admin_http
          assert_response_code(200, response)
        when :admin_oauth2_https
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/admins/auth/google_oauth2", response.headers["Location"])
        when :admin_oauth2_http
          assert_response_code(302, response)
          assert_oauth2_redirect_uri("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", response)
        when :api_backend_redirect_http
          assert_response_code(302, response)
          assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
        when :api_backend_redirect_https
          assert_response_code(302, response)
          assert_equal("https://frontend.foo:9081/hello?api_key=#{api_key}", response.headers["Location"])
        when :website_https
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/", response.headers["Location"])
        when :website_http
          assert_response_code(200, response)
        when :website_signup_https
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1:9081/signup/", response.headers["Location"])
        when :website_signup_http
          assert_response_code(200, response)
        else
          raise "Unhandled type: #{type}"
        end
      end
    end
  end

  def test_override_public_https_proto
    override_config(@default_config.deep_merge({
      :override_public_https_proto => "http",
    })) do
      headers = { "X-Forwarded-Proto" => "https" }
      responses = make_requests(headers)
      responses.each do |type, response|
        case(type)
        when :admin_https
          assert_response_code(301, response)
          assert_equal("http://127.0.0.1:9081/admin/login", response.headers["Location"])
        when :admin_http
          assert_response_code(200, response)
        when :admin_oauth2_https
          assert_response_code(301, response)
          assert_equal("http://127.0.0.1:9081/admins/auth/google_oauth2", response.headers["Location"])
        when :admin_oauth2_http
          assert_response_code(302, response)
          assert_oauth2_redirect_uri("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", response)
        when :api_backend_redirect_http
          assert_response_code(302, response)
          assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
        when :api_backend_redirect_https
          assert_response_code(302, response)
          assert_equal("http://frontend.foo:9080/hello?api_key=#{api_key}", response.headers["Location"])
        when :website_https
          assert_response_code(301, response)
          assert_equal("http://127.0.0.1:9080/", response.headers["Location"])
        when :website_http
          assert_response_code(200, response)
        when :website_signup_https
          assert_response_code(301, response)
          assert_equal("http://127.0.0.1:9080/signup/", response.headers["Location"])
        when :website_signup_http
          assert_response_code(200, response)
        else
          raise "Unhandled type: #{type}"
        end
      end
    end
  end

  def test_override_public_ports_defaults
    override_config(@default_config.deep_merge({
      :override_public_http_port => 80,
      :override_public_https_port => 443,
    })) do
      headers = {}
      responses = make_requests(headers)
      responses.each do |type, response|
        case(type)
        when :admin_https
          assert_response_code(200, response)
        when :admin_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1/admin/login", response.headers["Location"])
        when :admin_oauth2_https
          assert_response_code(302, response)
          assert_oauth2_redirect_uri("https://127.0.0.1/admins/auth/google_oauth2/callback", response)
        when :admin_oauth2_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1/admins/auth/google_oauth2", response.headers["Location"])
        when :api_backend_redirect_http
          assert_response_code(302, response)
          assert_equal("http://frontend.foo/hello?api_key=#{api_key}", response.headers["Location"])
        when :api_backend_redirect_https
          assert_response_code(302, response)
          assert_equal("https://frontend.foo/hello?api_key=#{api_key}", response.headers["Location"])
        when :website_https
          assert_response_code(200, response)
        when :website_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1/", response.headers["Location"])
        when :website_signup_https
          assert_response_code(200, response)
        when :website_signup_http
          assert_response_code(301, response)
          assert_equal("https://127.0.0.1/signup/", response.headers["Location"])
        else
          raise "Unhandled type: #{type}"
        end
      end
    end
  end

  def test_override_public_ports_and_proto_ssl_terminator
    override_config(@default_config.deep_merge({
      :override_public_http_port => 443,
      :override_public_http_proto => "https",
      :override_public_https_port => 443,
      :override_public_https_proto => "https",
    })) do
      headers = {}
      responses = make_requests(headers)
      responses.each do |type, response|
        case(type)
        when :admin_https, :admin_http
          assert_response_code(200, response)
        when :admin_oauth2_https, :admin_oauth2_http
          assert_response_code(302, response)
          assert_oauth2_redirect_uri("https://127.0.0.1/admins/auth/google_oauth2/callback", response)
        when :api_backend_redirect_http, :api_backend_redirect_https
          assert_response_code(302, response)
          assert_equal("https://frontend.foo/hello?api_key=#{api_key}", response.headers["Location"])
        when :website_https, :website_http
          assert_response_code(200, response)
        when :website_signup_https, :website_signup_http
          assert_response_code(200, response)
        else
          raise "Unhandled type: #{type}"
        end
      end
    end
  end

  private

  def assert_oauth2_redirect_uri(expected_uri, response)
    assert(response.headers["Location"])
    uri = Addressable::URI.parse(response.headers["Location"])
    assert_equal(expected_uri, uri.query_values["redirect_uri"])
  end

  def make_requests(headers)
    {
      :admin_https => admin_https_request(headers),
      :admin_http => admin_http_request(headers),
      :admin_oauth2_https => admin_oauth2_https_request(headers),
      :admin_oauth2_http => admin_oauth2_http_request(headers),
      :api_backend_redirect_http => api_backend_redirect_http(headers),
      :api_backend_redirect_https => api_backend_redirect_https(headers),
      :website_https => website_https_request(headers),
      :website_http => website_http_request(headers),
      :website_signup_https => website_signup_https_request(headers),
      :website_signup_http => website_signup_http_request(headers),
    }
  end

  def admin_https_request(headers = {})
    Typhoeus.get("https://127.0.0.1:9081/admin/login", keyless_http_options.deep_merge(:headers => headers))
  end

  def admin_http_request(headers = {})
    Typhoeus.get("http://127.0.0.1:9080/admin/login", keyless_http_options.deep_merge(:headers => headers))
  end

  def admin_oauth2_https_request(headers = {})
    Typhoeus.post("https://127.0.0.1:9081/admins/auth/google_oauth2", keyless_http_options.deep_merge(csrf_session).deep_merge(:headers => headers))
  end

  def admin_oauth2_http_request(headers = {})
    Typhoeus.post("http://127.0.0.1:9080/admins/auth/google_oauth2", keyless_http_options.deep_merge(csrf_session).deep_merge(:headers => headers))
  end

  def api_backend_redirect_http(headers = {})
    Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/front/end/path/redirect", http_options.deep_merge({
      :headers => {
        "Host" => "frontend.foo",
      },
      :params => {
        :to => "http://example.com/hello",
      },
    }).deep_merge(:headers => headers))
  end

  def api_backend_redirect_https(headers = {})
    Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/front/end/path/redirect", http_options.deep_merge({
      :headers => {
        "Host" => "frontend.foo",
      },
      :params => {
        :to => "https://example.com/hello",
      },
    }).deep_merge(:headers => headers))
  end

  def website_https_request(headers = {})
    Typhoeus.get("https://127.0.0.1:9081/", keyless_http_options.deep_merge(:headers => headers))
  end

  def website_http_request(headers = {})
    Typhoeus.get("http://127.0.0.1:9080/", keyless_http_options.deep_merge(:headers => headers))
  end

  def website_signup_https_request(headers = {})
    Typhoeus.get("https://127.0.0.1:9081/signup/", keyless_http_options.deep_merge(:headers => headers))
  end

  def website_signup_http_request(headers = {})
    Typhoeus.get("http://127.0.0.1:9080/signup/", keyless_http_options.deep_merge(:headers => headers))
  end
end

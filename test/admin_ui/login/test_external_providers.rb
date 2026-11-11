require_relative "../../test_helper"

class Test::AdminUi::Login::TestExternalProviders < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::AdminUiLogin
  include Minitest::Hooks

  def setup
    super
    setup_server

    once_per_class_setup do
      override_config_set({
        "web" => {
          "admin" => {
            "auth_strategies" => {
              "enabled" => [
                "facebook",
                "login.gov",
                "max.gov",
                "github",
                "gitlab",
                "google",
                "ldap",
              ],
            },
          },
        },
      })
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_forbids_first_time_admin_creation
    assert_equal(0, Admin.count)
    assert_first_time_admin_creation_not_found
  end

  def test_shows_message_when_no_admins_exist
    assert_equal(0, Admin.count)
    visit "/admin/login"
    assert_text("No admins currently exist")
  end

  def test_shows_external_login_links_in_order_and_no_local_fields
    visit "/admin/login"

    assert_text("Admin Sign In")

    # No local login fields
    refute_field("Email")
    refute_field("Password")
    refute_field("Remember me", :visible => :all)
    refute_link("Forgot your password?")
    refute_button(:text => /\ASign in\z/)

    # External login links
    assert_text("Sign in with")

    # Order matches enabled array order.
    buttons = page.all(".login-container .btn").map { |btn| btn.text }
    assert_equal([
      "Sign in with Facebook",
      "Sign in with login.gov",
      "Sign in with MAX.gov",
      "Sign in with GitHub",
      "Sign in with GitLab",
      "Sign in with Google",
      "Sign in with LDAP",
    ], buttons)
  end

  def test_local_login_endpoint_disabled
    admin = FactoryBot.create(:admin)
    response = Typhoeus.post("https://127.0.0.1:9081/admin/login", keyless_http_options.deep_merge(csrf_session).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :admin => {
          :username => admin.username,
          :password => "password123456",
        },
      },
    }))
    assert_response_code(404, response)
  end

  def test_no_password_field_on_admin_forms
    assert_no_password_fields_on_admin_forms
  end

  def test_external_auth_redirect_wildcard_host
    response = Typhoeus.post("https://127.0.0.1:9081/admins/auth/google_oauth2", keyless_http_options.deep_merge(csrf_session).deep_merge({
      :headers => {
        "Host" => "foobar.example.com",
      },
    }))
    assert_response_code(302, response)
    uri = Addressable::URI.parse(response.headers["Location"])
    assert_equal("https", uri.scheme)
    assert_equal("accounts.google.com", uri.host)
    assert_equal("/o/oauth2/v2/auth", uri.path)
    assert_equal([
      "client_id",
      "nonce",
      "prompt",
      "redirect_uri",
      "response_type",
      "scope",
      "state",
    ].sort, uri.query_values.keys.sort)
    assert_equal("test_fake_id", uri.query_values.fetch("client_id"))
    assert_equal("select_account", uri.query_values.fetch("prompt"))
    # Previously, we'd use the hostname being sent in, but as part of making
    # that stricter, we only use the `web.default_host` config, so first verify
    # that a hostname being sent in via header is not used.
    assert_equal("https://127.0.0.1:9081/admins/auth/google_oauth2/callback", uri.query_values.fetch("redirect_uri"))
    assert_equal("code", uri.query_values.fetch("response_type"))
    assert_equal("openid email", uri.query_values.fetch("scope"))
    assert_kind_of(String, uri.query_values.fetch("state"))
    assert_kind_of(String, uri.query_values.fetch("nonce"))
  end

  def test_external_auth_redirect_default_host
    # Verify that the `web.default_host` is used since the Host header is no
    # longer used.
    override_config({
      web: {
        default_host: "foo.example.com",
        admin: {
          auth_strategies: {
            enabled: [
              "google",
            ],
          },
        },
      },
    }) do
      response = Typhoeus.post("https://127.0.0.1:9081/admins/auth/google_oauth2", keyless_http_options.deep_merge(csrf_session))
      assert_response_code(302, response)
      uri = Addressable::URI.parse(response.headers["Location"])
      assert_equal("https://foo.example.com:9081/admins/auth/google_oauth2/callback", uri.query_values.fetch("redirect_uri"))
    end
  end

  [
    {
      :provider => :facebook,
      :login_button_text => "Sign in with Facebook",
      :mock_userinfo => MultiJson.dump({
        "email" => "{{username}}",
        "verified" => true,
      }),
      :mock_userinfo_unverified => MultiJson.dump({
        "email" => "{{username}}",
        "verified" => false,
      }),
    },
    {
      :provider => :github,
      :login_button_text => "Sign in with GitHub",
      :mock_userinfo => MultiJson.dump([
        {
          "email" => "other-email@example.com",
          "primary" => false,
          "verified" => true,
        },
        {
          "email" => "{{username}}",
          "primary" => true,
          "verified" => true,
        },
      ]),
      :mock_userinfo_unverified => MultiJson.dump([
        {
          "email" => "other-email@example.com",
          "primary" => false,
          "verified" => true,
        },
        {
          "email" => "{{username}}",
          "primary" => true,
          "verified" => false,
        },
      ]),
    },
    {
      :provider => :gitlab,
      :login_button_text => "Sign in with GitLab",
      :mock_userinfo => MultiJson.dump({
        "user" => {
          "email" => "{{username}}",
          "email_verified" => true,
        },
      }),
      :mock_userinfo_unverified => MultiJson.dump({
        "user" => {
          "email" => "{{username}}",
          "email_verified" => false,
        },
      }),
    },
    {
      :provider => :google_oauth2,
      :login_button_text => "Sign in with Google",
      :mock_userinfo => MultiJson.dump({
        "id_token" => {
          "email" => "{{username}}",
          "email_verified" => true,
        },
      }),
      :mock_userinfo_unverfied => MultiJson.dump({
        "id_token" => {
          "email" => "{{username}}",
          "email_verified" => false,
        },
      }),
    },
    {
      :provider => "login.gov",
      :login_button_text => "Sign in with login.gov",
      :mock_userinfo => MultiJson.dump({
        "id_token" => {
          "email" => "{{username}}",
          "email_verified" => true,
        },
      }),
      :mock_userinfo_unverfied => MultiJson.dump({
        "id_token" => {
          "email" => "{{username}}",
          "email_verified" => false,
        },
      }),
    },
    {
      :provider => :ldap,
      :login_button_text => "Sign in with LDAP",
      :mock_userinfo => MultiJson.dump({
        "sAMAccountName" => "{{username}}",
      }),
    },
    {
      :provider => "max.gov",
      :login_button_text => "Sign in with MAX.gov",
      :mock_userinfo => <<~EOS,
        <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
          <cas:authenticationSuccess>
            <cas:user>{{username}}</cas:user>
            <cas:attributes>
              <maxAttribute:MaxSecurityLevel>standard, securePlus2</maxAttribute:MaxSecurityLevel>
            </cas:attributes>
          </cas:authenticationSuccess>
        </cas:serviceResponse>
      EOS
    },
  ].each do |options|
    define_method("test_#{options.fetch(:provider)}_valid_admin") do
      assert_login_valid_admin(options)
    end

    define_method("test_#{options.fetch(:provider)}_case_insensitive_username_admin") do
      assert_login_case_insensitive_username_admin(options)
    end

    define_method("test_#{options.fetch(:provider)}_nonexistent_admin") do
      assert_login_nonexistent_admin(options)
    end

    if(options[:mock_userinfo_unverified])
      define_method("test_#{options.fetch(:provider)}_unverified_email") do
        assert_login_unverified_email_login(options)
      end
    end

    define_method("test_#{options.fetch(:provider)}_csrf_protection") do
      response = Typhoeus.get("https://127.0.0.1:9081/admins/auth/#{options.fetch(:provider)}", keyless_http_options)
      assert_response_code(404, response)

      response = Typhoeus.get("https://127.0.0.1:9081/admins/auth/#{options.fetch(:provider)}", keyless_http_options.deep_merge(csrf_session))
      assert_response_code(404, response)

      response = Typhoeus.post("https://127.0.0.1:9081/admins/auth/#{options.fetch(:provider)}", keyless_http_options)
      assert_response_code(422, response)

      response = Typhoeus.post("https://127.0.0.1:9081/admins/auth/#{options.fetch(:provider)}", keyless_http_options.deep_merge(csrf_session))
      if options.fetch(:provider) == :ldap
        assert_response_code(200, response)
      else
        assert_response_code(302, response)
      end
    end
  end

  private

  def assert_login_valid_admin(options)
    admin = FactoryBot.create(:admin, :username => "valid@example.com")
    data = options.fetch(:mock_userinfo).gsub("{{username}}", admin.username)

    mock_userinfo(data) do
      assert_login_permitted(options.fetch(:login_button_text), admin)
    end
  end

  def assert_login_case_insensitive_username_admin(options)
    admin = FactoryBot.create(:admin, :username => "hello@example.com")
    data = options.fetch(:mock_userinfo).gsub("{{username}}", "Hello@ExamplE.Com")

    mock_userinfo(data) do
      assert_login_permitted(options.fetch(:login_button_text), admin)
    end
  end

  def assert_login_nonexistent_admin(options)
    data = options.fetch(:mock_userinfo).gsub("{{username}}", "noadmin@example.com")

    mock_userinfo(data) do
      assert_login_forbidden(options.fetch(:login_button_text), "not authorized")
    end
  end

  def assert_login_unverified_email_login(options)
    admin = FactoryBot.create(:admin, :username => "unverified@example.com")
    data = options.fetch(:mock_userinfo_unverified).gsub("{{username}}", admin.username)

    mock_userinfo(data) do
      assert_login_forbidden(options.fetch(:login_button_text), "not verified")
    end
  end
end

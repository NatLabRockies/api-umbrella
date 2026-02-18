require_relative "../../test_helper"

class Test::AdminUi::Login::TestLogout < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server

    @admin = FactoryBot.create(:admin)
  end

  def test_logout
    admin_login(@admin)

    click_link("nav_gear_menu")
    click_link("Sign out")
    assert_text("Signed out successfully.")
    assert_match(%r{/admin/login\z}, page.current_url)
    assert_text("Admin Sign In")
  end

  def test_logout_requires_csrf_or_admin_token
    # Rejected with session but without CRSF token.
    response = Typhoeus.delete("https://127.0.0.1:9081/admin/logout", keyless_http_options.deep_merge(admin_session(@admin)))
    assert_response_code(422, response)

    # Allowed with session and with CRSF token.
    response = Typhoeus.delete("https://127.0.0.1:9081/admin/logout", keyless_http_options.deep_merge(admin_csrf_session(@admin)))
    assert_response_code(302, response)
    assert_equal("https://127.0.0.1:9081/admin/#/after-logout", response.headers.fetch("Location"))
    set_cookies = Array(response.headers["Set-Cookie"]).join("; ")
    assert_match(/_api_umbrella_session=;.*Expires=Thu, 01 Jan 1970 00:00:01 GMT/, set_cookies)
    data = parse_admin_session_client_cookie(response.headers["Set-Cookie"])
    assert_equal("Signed out successfully.", data["flash"]["info"]["message"])

    # Rejected with session and without CRSF token but with admin token.
    response = Typhoeus.delete("https://127.0.0.1:9081/admin/logout", keyless_http_options.deep_merge(admin_session(@admin)).deep_merge(admin_token(@admin)))
    assert_response_code(422, response)
  end
end

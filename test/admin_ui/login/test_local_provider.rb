require_relative "../../test_helper"

class Test::AdminUi::Login::TestLocalProvider < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::DelayServerResponses
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server

    @admin = FactoryBot.create(:admin)
  end

  def test_allows_first_time_admin_creation
    Admin.delete_all
    assert_equal(0, Admin.count)
    assert_first_time_admin_creation_allowed
  end

  def test_shows_local_login_fields_no_external_login_links
    visit "/admin/login"

    assert_text("Admin Sign In")

    # Local login fields
    assert_field("Email")
    assert_field("Password")
    assert_field("Remember me", :visible => :all)
    assert_link("Forgot your password?")
    assert_button("Sign in")

    # No external login links
    refute_text("Sign in with")
  end

  def test_password_fields_only_for_my_account
    assert_password_fields_on_my_account_admin_form_only
  end

  def test_login_process
    visit "/admin/login"
    fill_in "admin_username", :with => @admin.username
    fill_in "admin_password", :with => "password123456"
    click_button "sign_in"
    assert_logged_in(@admin)
  end

  def test_login_invalid_password
    visit "/admin/login"
    fill_in "admin_username", :with => @admin.username
    fill_in "admin_password", :with => "password1234567"
    click_button "sign_in"
    assert_text("Invalid email or password")
  end

  def test_login_empty_password
    visit "/admin/login"
    fill_in "admin_username", :with => @admin.username
    fill_in "admin_password", :with => "", :fill_options => { :clear => :backspace }
    click_button "sign_in"
    assert_text("Invalid email or password")
  end

  def test_login_empty_password_for_admin_without_password
    admin = FactoryBot.create(:admin, :password_hash => nil)
    assert_nil(admin.password_hash)

    visit "/admin/login"
    fill_in "admin_username", :with => admin.username
    fill_in "admin_password", :with => "", :fill_options => { :clear => :backspace }
    click_button "sign_in"
    assert_text("Invalid email or password")
  end

  def test_login_requires_csrf
    http_opts = {
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :admin => {
          :username => @admin.username,
          :password => "password123456",
        },
      },
    }

    response = Typhoeus.post("https://127.0.0.1:9081/admin/login", keyless_http_options.deep_merge(http_opts))
    assert_response_code(422, response)

    response = Typhoeus.post("https://127.0.0.1:9081/admin/login", keyless_http_options.deep_merge(csrf_session).deep_merge(http_opts))
    assert_response_code(302, response)
    data = parse_admin_session_cookie(response.headers["Set-Cookie"])
    assert_equal(@admin.id, data["admin_id"])
  end

  def test_login_redirects
    # Slow down the server side responses to validate the "Loading..." spinner
    # shows up (without slowing things down, it periodically goes away too
    # quickly for the tests to catch).
    delay_server_responses(0.5) do
      visit "/admin/"

      # Ensure we get the loading spinner until authentication takes place.
      assert_text("Loading...")

      # Navigation should not be visible while loading.
      refute_selector("nav")
      refute_text("Analytics")

      # Ensure that we eventually get redirected to the login page.
      assert_text("Admin Sign In")
    end
  end

  # Since we do some custom things related to the Rails asset path, make sure
  # everything is hooked up and the production cache-bused assets are served
  # up.
  def test_login_assets
    visit "/admin/login"
    assert_text("Admin Sign In")

    # Find the stylesheet on the Rails login page, which should have a
    # cache-busted URL (note that the href on the page appears to be relative,
    # but capybara seems to read it as absolute. That's fine, but noting it in
    # case Capybara's future behavior changes).
    stylesheet = find("link[rel=stylesheet]", :visible => :hidden)
    assert_match(%r{\Ahttps://127\.0\.0\.1:9081/web-assets/assets/login-\w{8}\.css\z}, stylesheet[:href])

    # Verify that the asset URL can be fetched and returns data.
    response = Typhoeus.get(stylesheet[:href], keyless_http_options)
    assert_response_code(200, response)
    assert_equal("text/css", response.headers["content-type"])
  end

  def test_update_my_account_without_changing_password
    admin_login(@admin)
    assert_nil(@admin.notes)
    visit "/admin/#/admins/#{@admin.id}/edit"

    fill_in "Notes", :with => "Foo"
    click_button "Save"
    assert_text("Successfully saved the admin")

    @admin.reload
    assert_equal("Foo", @admin.notes)
  end

  def test_update_my_account_with_password
    admin_login(@admin)
    original_password_hash = @admin.password_hash
    assert_nil(@admin.notes)
    visit "/admin/#/admins/#{@admin.id}/edit"

    fill_in "Notes", :with => "Foo"

    # Too short password
    fill_in "New Password", :with => "short"
    fill_in "Confirm New Password", :with => "short"
    click_button "Save"
    assert_text("Password: is too short (minimum is 14 characters)")
    @admin.reload
    assert_equal(original_password_hash, @admin.password_hash)
    assert_nil(@admin.notes)

    # Mismatched password
    fill_in "New Password", :with => "mismatch123456"
    fill_in "Confirm New Password", :with => "mismatcH123456"
    click_button "Save"
    assert_text("Password confirmation: doesn't match Password")
    @admin.reload
    assert_equal(original_password_hash, @admin.password_hash)
    assert_nil(@admin.notes)

    # No current password
    fill_in "Current Password", :with => "", :fill_options => { :clear => :backspace }
    fill_in "New Password", :with => "password234567"
    fill_in "Confirm New Password", :with => "password234567"
    click_button "Save"
    assert_text("Current password: can't be blank")
    @admin.reload
    assert_equal(original_password_hash, @admin.password_hash)
    assert_nil(@admin.notes)

    # Invalid current password
    fill_in "Current Password", :with => "password345678"
    fill_in "New Password", :with => "password234567"
    fill_in "Confirm New Password", :with => "password234567"
    click_button "Save"
    assert_text("Current password: is invalid")
    @admin.reload
    assert_equal(original_password_hash, @admin.password_hash)
    assert_nil(@admin.notes)

    # Valid password
    fill_in "Current Password", :with => "password123456"
    fill_in "New Password", :with => "password234567"
    fill_in "Confirm New Password", :with => "password234567"
    click_button "Save"
    assert_text("Successfully saved the admin")
    @admin.reload
    assert(@admin.password_hash)
    refute_equal(original_password_hash, @admin.password_hash)
    assert_equal("Foo", @admin.notes)

    # Stays signed in after changing password
    admin = FactoryBot.create(:admin, :notes => "After password change")
    visit "/admin/#/admins/#{admin.id}/edit"
    assert_field("Notes", :with => "After password change")
  end
end

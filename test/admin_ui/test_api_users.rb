require_relative "../test_helper"

class Test::AdminUi::TestApiUsers < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_form
    admin_login
    visit "/admin/#/api_users/new"

    # User Info
    fill_in "E-mail", :with => "example@example.com"
    fill_in "First Name", :with => "John"
    fill_in "Last Name", :with => "Doe"
    label_check "User agrees to the terms and conditions"

    # Rate Limiting
    select "Custom rate limits", :from => "Rate Limit"
    find("button", :text => /Add Rate Limit/).click
    within(".custom-rate-limits-table") do
      find(".rate-limit-duration-in-units").set("2")
      find(".rate-limit-duration-units").select("hours")
      find(".rate-limit-limit-by").select("IP Address")
      find(".rate-limit-limit").set("1500")
      custom_input_trigger_click(find(".rate-limit-response-headers", :visible => :all))
    end
    select "Rate limit by IP address", :from => "Limit By"

    # Permissions
    selectize_add "Roles", "some-user-role"
    selectize_add "Roles", "some-user-role2"
    fill_in "Restrict Access to IPs", :with => "127.0.0.1\n10.1.1.1/16"
    fill_in "Restrict Access to HTTP Referers", :with => "*.example.com/*\n*//example2.com/*"
    select "Disabled", :from => "Account Enabled"

    click_button("Save")
    assert_text("Successfully saved")
    page.execute_script("window.PNotifyRemoveAll()")

    user = ApiUser.order(:created_at => :desc).first
    visit "/admin/#/api_users/#{user.id}/edit"

    # User Info
    assert_field("E-mail", :with => "example@example.com")
    assert_field("First Name", :with => "John")
    assert_field("Last Name", :with => "Doe")

    # Rate Limiting
    assert_select("Rate Limit", :selected => "Custom rate limits")
    within(".custom-rate-limits-table") do
      assert_equal("2", find(".rate-limit-duration-in-units").value)
      assert_equal("hours", find(".rate-limit-duration-units").value)
      assert_equal("ip", find(".rate-limit-limit-by").value)
      assert_equal("1500", find(".rate-limit-limit").value)
      assert_equal(true, find(".rate-limit-response-headers", :visible => :all).checked?)
    end
    assert_select("Limit By", :selected => "Rate limit by IP address")

    # Permissions
    assert_selectize_field("Roles", :with => "some-user-role,some-user-role2")
    assert_field("Restrict Access to IPs", :with => "127.0.0.1\n10.1.1.1/16")
    assert_field("Restrict Access to HTTP Referers", :with => "*.example.com/*\n*//example2.com/*")
    assert_select("Account Enabled", :selected => "Disabled")
  end

  def test_metadata_timezone_display
    user = FactoryBot.create(:api_user, {
      :created_at => Time.parse("2015-01-16T06:06:28.816Z").utc,
      :updated_at => Time.parse("2015-07-16T06:09:33.273Z").utc,
    })
    admin_login
    visit "/admin/#/api_users/#{user.id}/edit"

    assert_text("Created: 2015-01-15 11:06 PM MST by ")
    assert_text("Last Updated: 2015-07-16 12:09 AM MDT by ")
  end
end

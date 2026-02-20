require_relative "../test_helper"

class Test::AdminUi::TestApis < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_saves_when_only_nested_fields_change
    api = FactoryBot.create(:api_backend_with_settings, :name => "Save Test API")
    assert_nil(api.settings.error_data)

    admin_login
    visit "/admin/#/apis"
    click_link "Save Test API"

    assert_equal("Save Test API", find_field("Name").value)

    find("legend button", :text => /Advanced Settings/).click
    fill_in_codemirror "API Key Missing", :with => "hello1: foo\nhello2: bar"

    click_button("Save")
    assert_text("Successfully saved")

    api = ApiBackend.find(api.id)
    assert_equal({
      "api_key_missing" => {
        "hello1" => "foo",
        "hello2" => "bar",
      },
    }, api.settings.error_data)
  end

  def test_loads_from_server_on_each_load
    api = FactoryBot.create(:api_backend_with_settings, :name => "Test Load API", :frontend_host => "example1.com")
    admin_login
    visit "/admin/#/apis"
    assert_text("Add API Backend")

    click_link "Test Load API"
    assert_equal("example1.com", find_field("Frontend Host").value)

    find("nav a", :text => /Configuration/).click
    find("nav a", :text => /API Backends/).click
    assert_text("Add API Backend")

    api.frontend_host = "example2.com"
    api.save!

    click_link "Test Load API"
    assert_equal("example2.com", find_field("Frontend Host").value)
  end

  def test_validation_error_when_all_servers_removed_from_existing_api
    api = FactoryBot.create(:api_backend)
    admin_login
    visit "/admin/#/apis/#{api.id}/edit"
    find("#servers_table a", :text => /Remove/).click
    click_button("OK")
    click_button("Save")
    assert_text("Must have at least one servers")

    api = ApiBackend.find(api.id)
    assert_equal(1, api.servers.length)
  end

  def test_validation_error_when_all_url_prefixes_removed_from_existing_api
    api = FactoryBot.create(:api_backend)
    admin_login
    visit "/admin/#/apis/#{api.id}/edit"
    find("#url_matches_table a", :text => /Remove/).click
    click_button("OK")
    click_button("Save")
    assert_text("Must have at least one url_matches")

    api = ApiBackend.find(api.id)
    assert_equal(1, api.url_matches.length)
  end

  def test_roles_override_checkbox_only_in_sub_settings
    admin_login
    visit "/admin/#/apis/new"

    find("legend button", :text => /Global Request Settings/).click
    refute_field('Override required roles from "Global Request Settings"', :visible => :all)

    find("legend button", :text => /Sub-URL Request Settings/).click
    find("button", :text => /Add URL Settings/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      assert_field('Override required roles from "Global Request Settings"', :visible => :all)
    end
  end

  def test_defaults_frontend_host_to_current_url_hostname
    admin_login
    visit "/admin/#/apis/new"
    assert_field("Frontend Host", :with => "127.0.0.1")
  end

  def test_form
    admin_login
    visit "/admin/#/apis/new"

    fill_in "Name", :with => "Testing API Backend"

    # Backend
    select "https", :from => "Backend Protocol"
    find("button", :text => /Add Server/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      fill_in "Host", :with => "google.com"
      assert_field("Port", :with => "443")
      click_button("OK")
    end

    # Host
    fill_in "Frontend Host", :with => "api.foo.com"
    fill_in "Backend Host", :with => "api.bar.com"

    # Matching URL Prefixes
    find("button", :text => /Add URL Prefix/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      fill_in "Frontend Prefix", :with => "/foo"
      fill_in "Backend Prefix", :with => "/bar"
      assert_text("Incoming Frontend Request: https://api.foo.com/fooexample.json?param=value")
      assert_text("Outgoing Backend Request: https://api.bar.com/barexample.json?param=value")
      click_button("OK")
    end

    # Global Request Settings
    find("legend button", :text => /Global Request Settings/).click
    fill_in "Append Query String Parameters", :with => "foo=bar"
    fill_in "Set Request Headers", :with => "X-Foo1: Bar\nX-Bar2: Foo"
    fill_in "HTTP Basic Authentication", :with => "foo:bar"
    select "Optional - HTTPS is optional", :from => "HTTPS Requirements"
    select "Disabled - API keys are optional", :from => "API Key Checks"
    select "None - API keys can be used without any verification", :from => "API Key Verification Requirements"
    selectize_add "Required Roles", "some-role"
    selectize_add "Required Roles", "some-role2"
    check "Via HTTP header"
    check "Via GET query parameter"
    select "Custom rate limits", :from => "Rate Limit"
    find("button", :text => /Add Rate Limit/).click
    within(".custom-rate-limits-table") do
      find(".rate-limit-duration-in-units").set("2")
      find(".rate-limit-duration-units").select("hours")
      find(".rate-limit-limit-by").select("IP Address")
      find(".rate-limit-limit").set("1500")
      custom_input_trigger_click(find(".rate-limit-response-headers", :visible => :all))
    end
    select "IP Only - API key rate limits are ignored (only IP based limits are applied)", :from => "Anonymous Rate Limit Behavior"
    select "API Key Only - IP based rate limits are ignored (only API key limits are applied)", :from => "Authenticated Rate Limit Behavior"
    fill_in "Default Response Headers", :with => "X-Foo2: Bar\nX-Bar2: Foo"
    fill_in "Override Response Headers", :with => "X-Foo3: Bar\nX-Bar3: Foo"

    # Sub-URL Request Settings
    find("legend button", :text => /Sub-URL Request Settings/).click
    find("button", :text => /Add URL Settings/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      select "OPTIONS", :from => "HTTP Method"
      fill_in "Regex", :with => "^/foo.*"
      select "Required - HTTP requests will receive a message to use HTTPS", :from => "HTTPS Requirements"
      select "Disabled - API keys are optional", :from => "API Key Checks"
      select "E-mail verification required - Existing API keys will break, only new API keys will work if verified", :from => "API Key Verification Requirements"
      selectize_add "Required Roles", "sub-role"
    end
    within(".modal-content") do
      check 'Override required roles from "Global Request Settings"'
      check "Via HTTP header"
      check "Via GET query parameter"
      select "Custom rate limits", :from => "Rate Limit"
      find("button", :text => /Add Rate Limit/).click
      within(".custom-rate-limits-table") do
        find(".rate-limit-duration-in-units").set("3")
        find(".rate-limit-duration-units").select("minutes")
        find(".rate-limit-limit-by").select("IP Address")
        find(".rate-limit-limit").set("100")
        custom_input_trigger_click(find(".rate-limit-response-headers", :visible => :all))
      end
      select "IP Only - API key rate limits are ignored (only IP based limits are applied)", :from => "Anonymous Rate Limit Behavior"
      select "API Key Only - IP based rate limits are ignored (only API key limits are applied)", :from => "Authenticated Rate Limit Behavior"
      fill_in "Default Response Headers", :with => "X-Sub-Foo2: Bar\nX-Sub-Bar2: Foo"
      fill_in "Override Response Headers", :with => "X-Sub-Foo3: Bar\nX-Sub-Bar3: Foo"
      click_button("OK")
    end

    # Advanced Requests Rewriting
    find("legend button", :text => /Advanced Requests Rewriting/).click
    find("button", :text => /Add Rewrite/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      select "Regular Expression", :from => "Matcher Type"
      select "PUT", :from => "HTTP Method"
      fill_in "Frontend Matcher", :with => "[0-9]+"
      fill_in "Backend Replacement", :with => "number"
      click_button("OK")
    end

    # Advanced Settings
    find("legend button", :text => /Advanced Settings/).click
    fill_in_codemirror "JSON Template", :with => '{"foo":"bar"}'
    fill_in_codemirror "XML Template", :with => "<foo>bar</foo>"
    fill_in_codemirror "CSV Template", :with => "foo,bar\nbar,foo"
    fill_in_codemirror "Common (All Errors)", :with => "foo0: bar0\nbar0: foo0"
    fill_in_codemirror "API Key Missing", :with => "foo1: bar1\nbar1: foo1"
    fill_in_codemirror "API Key Invalid", :with => "foo2: bar2\nbar2: foo2"
    fill_in_codemirror "API Key Disabled", :with => "foo3: bar3\nbar3: foo3"
    fill_in_codemirror "API Key Unauthorized", :with => "foo4: bar4\nbar4: foo4"
    fill_in_codemirror "Over Rate Limit", :with => "foo5: bar5\nbar5: foo5"
    fill_in_codemirror "HTTPS Required", :with => "foo6: bar6\nbar6: foo6"

    click_button("Save")
    assert_text("Successfully saved")

    api = ApiBackend.order(:created_at => :desc).first
    visit "/admin/#/apis/#{api.id}/edit"

    assert_field("Name", :with => "Testing API Backend")

    # Backend
    assert_select("Backend Protocol", :selected => "https")
    find("#servers_table a", :text => /Edit/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      assert_field("Host", :with => "google.com")
      assert_field("Port", :with => "443")
      click_button("OK")
    end

    # Host
    assert_field("Frontend Host", :with => "api.foo.com")
    assert_field("Backend Host", :with => "api.bar.com")

    # Matching URL Prefixes
    find("#url_matches_table a", :text => /Edit/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      assert_field("Frontend Prefix", :with => "/foo")
      assert_field("Backend Prefix", :with => "/bar")
      click_button("OK")
    end

    # Global Request Settings
    find("legend button", :text => /Global Request Settings/).click
    assert_field("Append Query String Parameters", :with => "foo=bar")
    assert_field("Set Request Headers", :with => "X-Foo1: Bar\nX-Bar2: Foo")
    assert_field("HTTP Basic Authentication", :with => "foo:bar")
    assert_select("HTTPS Requirements", :selected => "Optional - HTTPS is optional")
    assert_select("API Key Checks", :selected => "Disabled - API keys are optional")
    assert_select("API Key Verification Requirements", :selected => "None - API keys can be used without any verification")
    assert_selectize_field("Required Roles", :with => "some-role,some-role2")
    assert_checked_field("Via HTTP header", :visible => :all)
    assert_checked_field("Via GET query parameter", :visible => :all)
    assert_select("Rate Limit", :selected => "Custom rate limits")
    within(".custom-rate-limits-table") do
      assert_equal("2", find(".rate-limit-duration-in-units").value)
      assert_equal("hours", find(".rate-limit-duration-units").value)
      assert_equal("ip", find(".rate-limit-limit-by").value)
      assert_equal("1500", find(".rate-limit-limit").value)
      assert_equal(true, find(".rate-limit-response-headers", :visible => :all).checked?)
    end
    assert_select("Anonymous Rate Limit Behavior", :selected => "IP Only - API key rate limits are ignored (only IP based limits are applied)")
    assert_select("Authenticated Rate Limit Behavior", :selected => "API Key Only - IP based rate limits are ignored (only API key limits are applied)")
    assert_field("Default Response Headers", :with => "X-Foo2: Bar\nX-Bar2: Foo")
    assert_field("Override Response Headers", :with => "X-Foo3: Bar\nX-Bar3: Foo")

    # Sub-URL Request Settings
    find("legend button", :text => /Sub-URL Request Settings/).click
    find("#sub_settings_table a", :text => /Edit/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      assert_select("HTTP Method", :selected => "OPTIONS")
      assert_field("Regex", :with => "^/foo.*")
      assert_select("HTTPS Requirements", :selected => "Required - HTTP requests will receive a message to use HTTPS")
      assert_select("API Key Checks", :selected => "Disabled - API keys are optional")
      assert_select("API Key Verification Requirements", :selected => "E-mail verification required - Existing API keys will break, only new API keys will work if verified")
      assert_selectize_field("Required Roles", :with => "sub-role")
      assert_checked_field('Override required roles from "Global Request Settings"', :visible => :all)
      assert_checked_field("Via HTTP header", :visible => :all)
      assert_checked_field("Via GET query parameter", :visible => :all)
      assert_select("Rate Limit", :selected => "Custom rate limits")
      within(".custom-rate-limits-table") do
        assert_equal("3", find(".rate-limit-duration-in-units").value)
        assert_equal("minutes", find(".rate-limit-duration-units").value)
        assert_equal("ip", find(".rate-limit-limit-by").value)
        assert_equal("100", find(".rate-limit-limit").value)
        assert_equal(true, find(".rate-limit-response-headers", :visible => :all).checked?)
      end
      assert_select("Anonymous Rate Limit Behavior", :selected => "IP Only - API key rate limits are ignored (only IP based limits are applied)")
      assert_select("Authenticated Rate Limit Behavior", :selected => "API Key Only - IP based rate limits are ignored (only API key limits are applied)")
      assert_field("Default Response Headers", :with => "X-Sub-Foo2: Bar\nX-Sub-Bar2: Foo")
      assert_field("Override Response Headers", :with => "X-Sub-Foo3: Bar\nX-Sub-Bar3: Foo")
      click_button("OK")
    end

    # Advanced Requests Rewriting
    find("legend button", :text => /Advanced Requests Rewriting/).click
    find("#rewrites a", :text => /Edit/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      assert_select("Matcher Type", :selected => "Regular Expression")
      assert_select("HTTP Method", :selected => "PUT")
      assert_field("Frontend Matcher", :with => "[0-9]+")
      assert_field("Backend Replacement", :with => "number")
      click_button("OK")
    end

    # Advanced Settings
    find("legend button", :text => /Advanced Settings/).click
    assert_codemirror_field("JSON Template", :with => '{"foo":"bar"}')
    assert_codemirror_field("XML Template", :with => "<foo>bar</foo>")
    assert_codemirror_field("CSV Template", :with => "foo,bar\nbar,foo")
    assert_codemirror_field("API Key Missing", :with => "bar1: foo1\nfoo1: bar1")
    assert_codemirror_field("API Key Invalid", :with => "bar2: foo2\nfoo2: bar2")
    assert_codemirror_field("API Key Disabled", :with => "bar3: foo3\nfoo3: bar3")
    assert_codemirror_field("API Key Unauthorized", :with => "bar4: foo4\nfoo4: bar4")
    assert_codemirror_field("Over Rate Limit", :with => "bar5: foo5\nfoo5: bar5")
  end

  def test_edit_custom_rate_limits
    api = FactoryBot.create(:api_backend, {
      :settings => FactoryBot.build(:custom_rate_limit_api_backend_settings),
    })
    admin_login
    visit "/admin/#/apis/#{api.id}/edit"

    find("legend button", :text => /Global Request Settings/).click
    within(".custom-rate-limits-table") do
      assert_equal("1", find(".rate-limit-duration-in-units").value)
      assert_equal("minutes", find(".rate-limit-duration-units").value)
      assert_equal("ip", find(".rate-limit-limit-by").value)
      assert_equal("500", find(".rate-limit-limit").value)
      assert_equal(true, find(".rate-limit-response-headers", :visible => :all).checked?)

      find(".rate-limit-limit").set("200")
    end

    click_button("Save")
    assert_text("Successfully saved")

    api.reload

    assert_equal(1, api.settings.rate_limits.length)
    rate_limit = api.settings.rate_limits.first
    assert_equal(200, rate_limit.limit_to)
  end

  def test_nested_select_menu_behavior_inside_modals
    api = FactoryBot.create(:api_backend, :name => unique_test_id)
    admin_login
    visit "/admin/#/apis/#{api.id}/edit"

    # Add a sub-url setting.
    find("legend button", :text => /Sub-URL Request Settings/).click
    find("button", :text => /Add URL Settings/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      fill_in "Regex", :with => "^/foo.*"
      click_button("OK")
    end

    # Ensure the item got added to the table.
    assert_selector("#sub_settings_table")
    within("#sub_settings_table") do
      # "any" for the HTTP Method should be shown despite not being explicitly
      # selected (since it's the default/first option).
      assert_text("any")
      assert_text("^/foo.*")
    end

    # Save the API.
    click_button("Save")
    assert_text("Successfully saved")

    # Edit again.
    click_link api.name
    refute_text("Successfully saved")

    # Verify the sub-url setting in the table.
    find("legend button", :text => /Sub-URL Request Settings/).click
    assert_selector("#sub_settings_table")
    within("#sub_settings_table") do
      assert_text("any")
      assert_text("^/foo.*")
    end

    # Verify the sub-url setting in the modal and make explicit change the HTTP
    # method select.
    find("#sub_settings_table a", :text => /Edit/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      assert_select("HTTP Method", :selected => "Any")

      # Make another change.
      select "OPTIONS", :from => "HTTP Method"
      click_button("OK")
    end
    assert_selector("#sub_settings_table")
    within("#sub_settings_table") do
      assert_text("OPTIONS")
      assert_text("^/foo.*")
    end

    # Save the API.
    click_button("Save")
    assert_text("Successfully saved")

    # Edit again.
    click_link api.name
    refute_text("Successfully saved")

    # Verify all of the edit updates are displayed properly (we saw an issue
    # where the select menu handling didn't work properly on the second display
    # of an edited record).
    find("legend button", :text => /Sub-URL Request Settings/).click
    assert_selector("#sub_settings_table")
    within("#sub_settings_table") do
      assert_text("OPTIONS")
      assert_text("^/foo.*")
    end
    find("#sub_settings_table a", :text => /Edit/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      assert_select("HTTP Method", :selected => "OPTIONS")
    end
  end
end

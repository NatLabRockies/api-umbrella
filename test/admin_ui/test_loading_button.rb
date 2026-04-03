require_relative "../test_helper"

class Test::AdminUi::TestLoadingButton < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::DelayServerResponses
  include ApiUmbrellaTestHelpers::Setup
  include Minitest::Hooks

  def setup
    super
    setup_server

    publish_default_config_version
  end

  def after_all
    super
    publish_default_config_version
  end

  def test_save_button
    admin_login

    # Slow down the server side responses so there's time to validate the
    # button behavior.
    delay_server_responses(0.5) do
      visit("/admin/#/api_scopes/new")

      fill_in("Name", :with => unique_test_id)
      fill_in("Host", :with => "example.com")
      fill_in("Path Prefix", :with => "/foo/")

      assert_loading_button("Save", "Saving...")
      assert_text("Successfully saved")
      find(".alert.alert-dismissible .btn-close").click
      refute_text("Successfully saved")

      # Verify that after the first save, the button gets reset and can be used
      # again when editing the same record.
      api_scope = ApiScope.find_by!(:name => unique_test_id)
      assert_equal("example.com", api_scope.host)

      click_link api_scope.name
      fill_in("Host", :with => "foo.example.com")
      assert_loading_button("Save", "Saving...")
      assert_text("Successfully saved")

      api_scope.reload
      assert_equal("foo.example.com", api_scope.host)
    end
  end

  def test_publish_button
    # Slow down the server side responses so there's time to validate the
    # button behavior.
    delay_server_responses(0.5) do
      admin_login

      FactoryBot.create(:api_backend)
      visit "/admin/#/config/publish"
      assert_loading_button("Publish", "Publishing...")
      assert_text("Successfully published the configuration")
      find(".alert.alert-dismissible .btn-close").click
      refute_text("Successfully published the configuration")

      # Verify that after the first publish, the button gets reset and can be
      # used again.
      FactoryBot.create(:api_backend)
      find("nav a", :text => /Configuration/).click
      find("nav a", :text => /API Backends/).click
      assert_text("Add API Backend")
      find("nav a", :text => /Configuration/).click
      find("nav a", :text => /Publish Changes/).click
      assert_loading_button("Publish", "Publishing...")
      assert_text("Successfully published the configuration")
      find(".alert.alert-dismissible .btn-close").click
      refute_text("Successfully published the configuration")
    end
  end

  private

  def assert_loading_button(default_text, loading_text)
    # Ensure the initial state of the button (non-loading).
    assert_selector("button:not(:disabled)", :text => default_text)
    refute_selector("button", :text => loading_text)

    # Trigger the button action.
    click_button(default_text)

    # Ensure the button toggles to the loading state and becomes disabled.
    assert_selector("button:disabled", :text => loading_text)
    refute_selector("button", :text => default_text)
  end
end

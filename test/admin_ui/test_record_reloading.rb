require_relative "../test_helper"

class Test::AdminUi::TestRecordReloading < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_repeated_edits
    user = FactoryBot.create(:api_user, :email => "#{unique_test_id}@example.com")
    assert_nil(user.use_description)

    # First edit
    admin_login
    visit "/admin/#/api_users/#{user.id}/edit"

    assert_field "Purpose", :with => ""
    fill_in "Purpose", :with => "foo"

    click_button "Save"
    assert_text("Successfully saved")

    user.reload
    assert_equal("foo", user.use_description)

    # Second edit
    click_link user.email
    refute_text("Successfully saved")

    assert_field "Purpose", :with => "foo"
    fill_in "Purpose", :with => "foobar"

    click_button "Save"
    assert_text("Successfully saved")

    user.reload
    assert_equal("foobar", user.use_description)

    # Third edit
    click_link user.email
    refute_text("Successfully saved")

    assert_field "Purpose", :with => "foobar"
    fill_in "Purpose", :with => "foobarbaz"

    click_button "Save"
    assert_text("Successfully saved")

    user.reload
    assert_equal("foobarbaz", user.use_description)
  end

  def test_server_side_changes
    user = FactoryBot.create(:api_user, :email => "#{unique_test_id}@example.com")
    assert_nil(user.use_description)

    # Check initial form, triggering record load.
    admin_login
    visit "/admin/#/api_users/#{user.id}/edit"
    assert_field "Purpose", :with => ""

    # Navigate away from the edit page
    find("nav a", :text => "Users").click
    find("nav a", :text => "API Users").click
    assert_text("Add New API User")

    # Make a server side edit to the record.
    user.use_description = "Hello"
    user.save!

    # Navigate back to the form and ensure it refreshed from the server.
    click_link user.email
    assert_field "Purpose", :with => "Hello"
  end

  def test_discarded_changes
    user = FactoryBot.create(:api_user, :email => "#{unique_test_id}@example.com")
    assert_nil(user.use_description)

    # Enter some initial edits, but don't save.
    admin_login
    visit "/admin/#/api_users/#{user.id}/edit"
    assert_field "Purpose", :with => ""
    fill_in "Purpose", :with => "Nevermind"

    # Navigate away from the edit page, accepting the unsaved changes alert.
    find("nav a", :text => "Users").click
    alert_message = accept_alert do
      find("nav a", :text => "API Users").click
    end
    assert_equal("Unsaved changes! Are you sure you would like to continue?", alert_message)
    assert_text("Add New API User")

    # Ensure nothing was saved.
    user.reload
    assert_nil(user.use_description)

    # Navigate back to the form and ensure it doesn't retain the user's
    # discarded changes.
    click_link user.email
    assert_field "Purpose", :with => ""
  end
end

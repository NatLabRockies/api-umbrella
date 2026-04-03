require_relative "../../test_helper"

class Test::AdminUi::Login::TestUsernameNotEmail < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::AdminAuth
  include Minitest::Hooks

  def setup
    super
    setup_server

    FactoryBot.create(:admin)
    once_per_class_setup do
      override_config_set({
        "web" => {
          "admin" => {
            "username_is_email" => false,
          },
        },
      })
    end
  end

  def after_all
    super
    override_config_reset
  end

  def test_username_label_on_login
    visit "/admin/login"
    assert_text("Admin Sign In")

    assert_text("Username")
    refute_text("Email")
  end

  def test_username_label_on_listing
    admin_login
    visit "/admin/#/admins"
    assert_text("Admins")

    assert_text("Username")
    refute_text("Email")
  end

  def test_username_and_email_label_on_form
    admin_login
    visit "/admin/#/admins/new"
    assert_text("Add Admin")

    assert_field("Username", :count => 1)
    assert_field("Email", :count => 1)
  end

  def test_allows_different_username_and_email
    admin_login

    # Create admin
    visit "/admin/#/admins/new"
    assert_text("Add Admin")
    fill_in "Username", :with => unique_test_id.upcase
    fill_in "Email", :with => "#{unique_test_id.upcase}@example.com"
    check "Superuser"
    click_button "Save"
    assert_text("Successfully saved the admin")

    # Find admin record, and ensure username and email are different.
    admin = Admin.where(:username => unique_test_id.downcase).first
    assert(admin)
    assert_equal(unique_test_id.downcase, admin.username)
    assert_equal("#{unique_test_id.downcase}@example.com", admin.email)

    # Edit admin
    visit "/admin/#/admins/#{admin.id}/edit"
    refute_text("Successfully saved the admin")
    assert_text("Edit Admin")
    assert_field("Username", :with => unique_test_id.downcase)
    assert_field("Email", :with => "#{unique_test_id.downcase}@example.com")
    fill_in "Username", :with => "#{unique_test_id.upcase}-update"
    fill_in "Email", :with => "#{unique_test_id.upcase}-different@example.com"
    click_button "Save"
    assert_text("Successfully saved the admin")

    # Ensure edits still keep things different.
    admin.reload
    assert_equal("#{unique_test_id.downcase}-update", admin.username)
    assert_equal("#{unique_test_id.downcase}-different@example.com", admin.email)
  end
end

require_relative "../../test_helper"

class Test::AdminUi::Login::TestUsernameIsEmail < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::AdminAuth

  def setup
    super
    setup_server

    @admin = FactoryBot.create(:admin)
  end

  def test_email_label_on_login
    visit "/admin/login"
    assert_text("Admin Sign In")

    assert_text("Email")
    refute_text("Username")
  end

  def test_email_label_on_listing
    admin_login
    visit "/admin/#/admins"
    assert_text("Admins")

    assert_text("Email")
    refute_text("Username")
  end

  def test_email_label_on_form
    admin_login
    visit "/admin/#/admins/new"
    assert_text("Add Admin")

    assert_field("Email", :count => 1)
    refute_field("Username")
  end

  def test_keeps_username_and_email_in_sync
    admin_login

    # Create admin
    visit "/admin/#/admins/new"
    assert_text("Add Admin")
    fill_in "Email", :with => "#{unique_test_id.upcase}@example.com"
    check "Superuser"
    click_button "Save"
    assert_text("Successfully saved the admin")

    # Find admin record, and ensure username and email are the same.
    admin = Admin.where(:username => "#{unique_test_id.downcase}@example.com").first
    assert(admin)
    assert_equal("#{unique_test_id.downcase}@example.com", admin.username)
    assert_equal(admin.username, admin.email)

    # Edit admin
    visit "/admin/#/admins/#{admin.id}/edit"
    assert_text("Edit Admin")
    assert_field("Email", :with => "#{unique_test_id.downcase}@example.com")
    fill_in "Email", :with => "#{unique_test_id.upcase}-update@example.com"
    click_button "Save"
    assert_text("Successfully saved the admin")

    # Ensure edits still keep things the same.
    admin.reload
    assert_equal("#{unique_test_id.downcase}-update@example.com", admin.username)
    assert_equal(admin.username, admin.email)
  end
end

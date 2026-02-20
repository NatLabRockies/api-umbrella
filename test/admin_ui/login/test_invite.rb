require_relative "../../test_helper"

class Test::AdminUi::Login::TestInvite < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::SentEmails

  def setup
    super
    setup_server

    clear_all_test_emails
  end

  def test_defaults_to_sending_invite_for_new_accounts
    admin_login

    # Create admin
    visit "/admin/#/admins/new"
    assert_text("Add Admin")
    fill_in "Email", :with => "#{unique_test_id}@example.com"
    assert_equal(true, find_field("Send invite email", :visible => :all).checked?)
    check "Superuser"
    click_button "Save"
    assert_text("Successfully saved the admin")

    # Logout
    ::Capybara.reset_session!

    # Find admin record
    admin = Admin.where(:username => "#{unique_test_id.downcase}@example.com").first
    assert(admin)

    # Find sent email
    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))
    message = messages.fetch("messages").first

    # To
    assert_equal(["#{unique_test_id.downcase}@example.com"], message.fetch("headers").fetch("To"))

    # Subject
    assert_equal("API Umbrella Admin Access", message.fetch("Subject"))

    # Password reset URL in body
    assert_match(%r{https://127.0.0.1:9081/admins/password/edit\?[^" ]+&amp;[^" ]+}, message.fetch("HTML"))
    assert_match(%r{https://127.0.0.1:9081/admins/password/edit\?[^" ;]+&[^" ;]+}, message.fetch("Text"))

    html_reset_url = Addressable::URI.parse(CGI.unescapeHTML(message.fetch("HTML").match(%r{https://127.0.0.1:9081/admins/password/edit[^" ]+})[0]))
    assert_equal([
      "invite",
      "reset_password_token",
    ].sort, html_reset_url.query_values.keys.sort)
    assert_equal("true", html_reset_url.query_values.fetch("invite"))
    assert_match(/^\w{24}$/, html_reset_url.query_values.fetch("reset_password_token"))

    plain_reset_url = Addressable::URI.parse(message.fetch("Text").match(%r{https://127.0.0.1:9081/admins/password/edit[^" ;]+})[0])
    assert_equal([
      "invite",
      "reset_password_token",
    ].sort, plain_reset_url.query_values.keys.sort)
    assert_equal("true", plain_reset_url.query_values.fetch("invite"))
    assert_match(/^\w{24}$/, plain_reset_url.query_values.fetch("reset_password_token"))

    # Follow link to reset URL
    reset_url = message.fetch("Text").match(%r{/admins/password/edit\?[^" ;]+})[0]
    visit reset_url
    fill_in "New Password", :with => "password123456"
    fill_in "Confirm New Password", :with => "password123456"
    click_button "Change My Password"

    # Ensure the user gets logged in.
    assert_logged_in(admin)
  end

  def test_invites_can_be_skipped_for_new_users
    admin_login

    # Create admin
    visit "/admin/#/admins/new"
    assert_text("Add Admin")
    fill_in "Email", :with => "#{unique_test_id}@example.com"
    uncheck "Send invite email"
    check "Superuser"
    click_button "Save"
    assert_text("Successfully saved the admin")

    # Find admin record
    admin = Admin.where(:username => "#{unique_test_id.downcase}@example.com").first
    assert(admin)

    # No email
    assert_equal(0, sent_emails.fetch("total"))
  end

  def test_invites_can_be_resent
    admin_login

    admin = FactoryBot.create(:admin)
    assert_nil(admin.notes)

    # Ensure edits don't resend invites by default.
    visit "/admin/#/admins/#{admin.id}/edit"
    assert_text("Edit Admin")
    assert_field("Email", :with => admin.email)
    fill_in "Notes", :with => "Foo"
    assert_equal(false, find_field("Resend invite email", :visible => :all).checked?)
    click_button "Save"
    assert_text("Successfully saved the admin")

    admin.reload
    assert_equal("Foo", admin.notes)
    assert_equal(0, sent_emails.fetch("total"))

    # Force the invite to be resent.
    visit "/admin/#/admins/#{admin.id}/edit"
    assert_text("Edit Admin")
    assert_field("Email", :with => admin.email)
    fill_in "Notes", :with => "Bar"
    assert_equal(false, find_field("Resend invite email", :visible => :all).checked?)
    label_check "Resend invite email"
    click_button "Save"
    assert_text("Successfully saved the admin")

    admin.reload
    assert_equal("Bar", admin.notes)
    messages = sent_emails
    assert_equal(1, messages.fetch("total"))
    message = messages.fetch("messages").first
    assert_equal("API Umbrella Admin Access", message.fetch("Subject"))

    admin.update(:current_sign_in_at => Time.now.utc)
    visit "/admin/#/admins/#{admin.id}/edit"
    assert_text("Edit Admin")
    assert_field("Email", :with => admin.email)
    refute_field("Resend invite email", :visible => :all)
  end
end

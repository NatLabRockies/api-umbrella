require_relative "../test_helper"

class Test::StaticSite::TestSignup < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::SentEmails

  def setup
    super
    setup_server

    clear_all_test_emails
  end

  def test_submission
    visit "/signup/"
    assert_text("API Key Sign Up")

    # Because these elements are inside the shadow DOM, testing is a bit harder
    # with Capybara, so we can't rely on the normal `fill_in` usage currently,
    # so that's why this testing is a bit more manual.
    within find("#api_umbrella_signup .api-umbrella-signup-embed-content-container").shadow_root do
      first_name_input = find("input[name='user[first_name]']")
      first_name_input.set "Foo"
      first_name_label = find("label[for='#{first_name_input[:id]}']")
      assert_equal("First Name *", first_name_label.text)

      last_name_input = find("input[name='user[last_name]']")
      last_name_input.set "Bar"
      last_name_label = find("label[for='#{last_name_input[:id]}']")
      assert_equal("Last Name *", last_name_label.text)

      email_input = find("input[name='user[email]']")
      email_input.set "foo@example.com"
      email_label = find("label[for='#{email_input[:id]}']")
      assert_equal("Email *", email_label.text)

      terms_input = find("input[name='user[terms_and_conditions]']")
      terms_input.click
      terms_label = find("label[for='#{terms_input[:id]}']")
      assert_equal("I have read and agree to the terms and conditions.", terms_label.text)

      submit_button = find("button[type=submit]")
      assert_equal("Sign up", submit_button.text)
      submit_button.click

      assert_text("Your API key for foo@example.com is:")

      user = ApiUser.order(:created_at => :asc).last
      assert(user)
      assert(user.api_key)
      assert_equal("Foo", user.first_name)
      assert_equal("Bar", user.last_name)
      assert_equal("foo@example.com", user.email)
      assert_text(user.api_key)
    end

    messages = sent_emails
    assert_equal(1, messages.fetch("total"))
  end
end

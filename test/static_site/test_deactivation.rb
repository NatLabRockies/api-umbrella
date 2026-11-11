require_relative "../test_helper"

class Test::StaticSite::TestDeactivation < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::SentEmails

  def setup
    super
    setup_server

    clear_all_test_emails
  end

  def test_entire_flow
    api_user = FactoryBot.create(:api_user)
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)
    assert_nil(api_user.disabled_at)

    visit "/signup/"
    assert_text("API Key Sign Up")

    # Because these elements are inside the shadow DOM, testing is a bit harder
    # with Capybara, so we can't rely on the normal `fill_in` usage currently,
    # so that's why this testing is a bit more manual.
    within find("#api_umbrella_signup .api-umbrella-signup-embed-content-container").shadow_root do
      trigger_link = find("a", text: "begin API key deactivation")
      trigger_link.click
    end

    within find("#api-umbrella-signup-embed-body-container", visible: :all).shadow_root do
      within find("#api_umbrella_form_modal") do
        api_key_input = find("input[name='user[api_key]']")
        api_key_input.set api_user.api_key.swapcase

        email_input = find("input[name='user[email]']")
        email_input.set api_user.email

        submit_button = find("button[type=submit]")
        assert_equal("Send confirmation email", submit_button.text)
        submit_button.click
      end

      api_user.reload
      assert_nil(api_user.deactivation_token_hash)
      assert_nil(api_user.deactivation_sent_at)
      assert_nil(api_user.disabled_at)

      within find("#api_umbrella_alert_modal") do
        assert_text("Email: a matching email and API key could not be found")

        find("button", text: "OK").click
      end

      within find("#api_umbrella_form_modal") do
        api_key_input = find("input[name='user[api_key]']")
        api_key_input.set api_user.api_key

        submit_button = find("button[type=submit]")
        assert_equal("Send confirmation email", submit_button.text)
        submit_button.click

        assert_text("Instructions for deactivating your API key have been emailed to #{api_user.email}")
      end
    end

    api_user.reload
    assert(api_user.deactivation_token_hash)
    assert(api_user.deactivation_sent_at)
    assert_nil(api_user.disabled_at)

    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))
    message = messages.fetch("messages").first

    url_matcher = %r{^(https://127\.0\.0\.1:9081/signup/#/confirm-deactivation\?token=\w+)$}
    assert_match(url_matcher, message.fetch("Text"))
    url = message.fetch("Text").match(url_matcher)[1]

    visit url

    within find("#api-umbrella-signup-embed-body-container", visible: :all).shadow_root do
      within find("#api_umbrella_form_modal") do
        assert_text("To complete the deactivation process")
        assert_text("API Key: ...#{api_user.api_key_suffix}")
        assert_text("Key Created: #{api_user.created_at.utc.iso8601}")

        api_user.reload
        assert(api_user.deactivation_token_hash)
        assert(api_user.deactivation_sent_at)
        assert_nil(api_user.disabled_at)

        submit_button = find("button[type=submit]")
        assert_equal("Deactivate this API key", submit_button.text)
        submit_button.click

        assert_text("Your API key ending in #{api_user.api_key_suffix} is now deactivated.")
      end
    end

    api_user.reload
    assert_nil(api_user.deactivation_token_hash)
    assert_nil(api_user.deactivation_sent_at)
    assert(api_user.disabled_at)
  end
end

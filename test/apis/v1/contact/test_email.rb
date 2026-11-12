require_relative "../../../test_helper"

class Test::Apis::V1::Contact::TestEmail < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::SentEmails

  def setup
    super
    setup_server

    clear_all_test_emails
  end

  def test_sends_email
    user = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-contact-form"],
    })

    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/contact.json", http_options.deep_merge({
      :headers => {
        "X-Api-Key" => user.api_key,
        "Content-Type" => "application/x-www-form-urlencoded",
      },
      :body => {
        :contact => {
          :name => "Foo",
          :email => "foo@example.com",
          :api => "Example API",
          :subject => "Support",
          :message => "Message body",
        },
      },
    }))
    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(["submitted"], data.keys)
    assert_match_iso8601(data.fetch("submitted"))

    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))
    message = messages.fetch("messages").first

    assert_equal(["default-test-contact-email@example.com"], message.fetch("headers").fetch("To"))
    assert_equal("API Umbrella Contact Message from foo@example.com", message.fetch("Subject"))
    assert_equal(["noreply@127.0.0.1"], message.fetch("headers").fetch("From"))
    assert_equal(["foo@example.com"], message.fetch("headers").fetch("Reply-To"))
    assert_match("Name: Foo\nEmail: foo@example.com\nAPI: Example API\nSubject: Support\n\n-------------------------------------\n\nMessage body\n\n-------------------------------------", message.fetch("Text"))
    assert_equal("", message.fetch("HTML"))
  end
end

require_relative "../../../test_helper"

class Test::Apis::V1::Users::TestCreateWelcomeEmail < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::SentEmails

  def setup
    super
    setup_server

    clear_all_test_emails
  end

  def test_sends_email_when_enabled
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
        :options => { :send_welcome_email => true },
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "send_welcome_email" => true,
      "site_name" => "API Umbrella",
    }, data.fetch("options"))

    assert_equal(1, sent_emails.fetch("total"))
  end

  def test_no_email_when_disabled
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
        :options => { :send_welcome_email => false },
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "send_welcome_email" => false,
      "site_name" => "API Umbrella",
    }, data.fetch("options"))

    assert_equal(0, sent_emails.fetch("total"))
  end

  def test_no_email_when_unknown_value
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
        :options => { :send_welcome_email => 1 },
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "send_welcome_email" => false,
      "site_name" => "API Umbrella",
    }, data.fetch("options"))

    assert_equal(0, sent_emails.fetch("total"))
  end

  def test_no_email_by_default
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "site_name" => "API Umbrella",
    }, data.fetch("options"))

    assert_equal(0, sent_emails.fetch("total"))
  end

  def test_sends_email_when_user_attribute_has_any_value
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(admin_token).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user).merge({
          :send_welcome_email => "0",
        }),
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "send_welcome_email" => true,
      "site_name" => "API Umbrella",
    }, data.fetch("options"))

    assert_equal(1, sent_emails.fetch("total"))
  end

  def test_non_admin
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
        :options => { :send_welcome_email => true },
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "send_welcome_email" => true,
      "site_name" => "API Umbrella",
    }, data.fetch("options"))

    assert_equal(1, sent_emails.fetch("total"))
  end

  def test_email_verification
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
        :options => {
          :send_welcome_email => true,
          :verify_email => true,
          :example_api_url => "https://localhost/api.json?api_key={{api_key}}&test=1",
        },
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)

    assert_nil(data.fetch("user")["api_key"])
    user = ApiUser.find(data["user"]["id"])
    refute_match(user.api_key, response.body)

    assert_equal({
      "send_welcome_email" => true,
      "site_name" => "API Umbrella",
      "verify_email" => true,
    }, data.fetch("options"))

    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))
    message = messages.fetch("messages").first

    refute_nil(user.api_key)
    refute_match("https://localhost/api.json", message.fetch("HTML"))
    refute_match("https://localhost/api.json", message.fetch("Text"))
  end

  def test_default_content
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user),
        :options => { :send_welcome_email => true },
      },
    }))
    assert_response_code(201, response)
    data = MultiJson.load(response.body)
    assert_equal({
      "send_welcome_email" => true,
      "site_name" => "API Umbrella",
    }, data.fetch("options"))

    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))

    user = ApiUser.find(data["user"]["id"])
    message = messages.fetch("messages").first

    # To
    refute_nil(user.email)
    assert_equal([user.email], message.fetch("headers").fetch("To"))

    # Greeting
    assert_match("Hi,</p>", message.fetch("HTML"))
    assert_match("Hi,", message.fetch("Text"))

    assert_match("Your API key for <strong>#{user.email}</strong> is:</p>", message.fetch("HTML"))
    assert_match("Your API key for #{user.email} is:", message.fetch("Text"))

    # API key
    refute_nil(user.api_key)
    assert_match(user.api_key, message.fetch("HTML"))
    assert_match(user.api_key, message.fetch("Text"))

    # Subject
    assert_equal("Your API key", message.fetch("Subject"))

    # From
    assert_equal(["noreply@localhost"], message.fetch("headers").fetch("From"))

    # Example API URL
    refute_match("Here's an example", message.fetch("HTML"))
    refute_match("Here's an example", message.fetch("Text"))

    # Contact URL
    assert_match("please contact us.", message.fetch("Text"))
    assert_match("please contact us.", message.fetch("HTML"))

    # Support footer
    assert_match("Account Email: #{user.email}", message.fetch("HTML"))
    assert_match("Account Email: #{user.email}", message.fetch("Text"))

    assert_match("Account ID: #{user.id}", message.fetch("HTML"))
    assert_match("Account ID: #{user.id}", message.fetch("Text"))
  end

  def test_customized_content
    prepend_api_backends([
      {
        :frontend_host => "example.com",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
      },
    ]) do
      response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
        :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
        :body => {
          :user => FactoryBot.attributes_for(:api_user),
          :options => {
            :send_welcome_email => true,
            :site_name => "External Example",
            :email_from_name => "Tester",
            :email_from_address => "test@example.com",
            :example_api_url => "https://example.com/api.json?api_key={{api_key}}&test=1",
            :contact_url => "https://example.com/contact-us",
          },
        },
      }))
      assert_response_code(201, response)
      data = MultiJson.load(response.body)
      assert_equal({
        "contact_url" => "https://example.com/contact-us",
        "email_from_address" => "test@example.com",
        "email_from_name" => "Tester",
        "example_api_url" => "https://example.com/api.json?api_key=#{data.fetch("user").fetch("api_key")}&test=1",
        "example_api_url_formatted_html" => "https://example.com/api.json?<strong>api_key=#{data.fetch("user").fetch("api_key")}</strong>&amp;test=1",
        "send_welcome_email" => true,
        "site_name" => "External Example",
      }, data.fetch("options"))

      messages = sent_email_contents
      assert_equal(1, messages.fetch("total"))

      user = ApiUser.find(data["user"]["id"])
      message = messages.fetch("messages").first

      # To
      refute_nil(user.email)
      assert_equal([user.email], message.fetch("headers").fetch("To"))

      # API key
      refute_nil(user.api_key)
      assert_match(user.api_key, message.fetch("HTML"))
      assert_match(user.api_key, message.fetch("Text"))

      # Subject
      assert_equal("Your API key", message.fetch("Subject"))

      # From
      assert_equal(["test@example.com"], message.fetch("headers").fetch("From"))

      # URL Example
      refute_match("Here's an example", message.fetch("HTML"))
      refute_match("Here's an example", message.fetch("Text"))
      refute_match("https://example.com/api.json", message.fetch("HTML"))
      refute_match("https://example.com/api.json", message.fetch("Text"))

      # Contact URL
      assert_match(%(please <a href="https://example.com/contact-us">contact us</a>.), message.fetch("HTML"))
      assert_match("please contact us ( https://example.com/contact-us ).", message.fetch("Text"))
    end
  end

  def test_html_escaping
    response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
      :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      :body => {
        :user => FactoryBot.attributes_for(:api_user, :email => "foo&bar@example.com", :first_name => "Test&First", :last_name => "Test&Last"),
        :options => { :send_welcome_email => true },
      },
    }))
    assert_response_code(201, response)

    messages = sent_email_contents
    assert_equal(1, messages.fetch("total"))

    data = MultiJson.load(response.body)
    user = ApiUser.find(data["user"]["id"])
    message = messages.fetch("messages").first

    # Greeting
    assert_match("Hi,</p>", message.fetch("HTML"))
    assert_match("Hi,", message.fetch("Text"))

    assert_match("Your API key for <strong>foo&amp;bar@example.com</strong> is:</p>", message.fetch("HTML"))
    assert_match("Your API key for foo&bar@example.com is:", message.fetch("Text"))

    # Support footer
    assert_match("Account Email: foo&amp;bar@example.com", message.fetch("HTML"))
    assert_match("Account Email: foo&bar@example.com", message.fetch("Text"))

    assert_match("Account ID: #{user.id}", message.fetch("HTML"))
    assert_match("Account ID: #{user.id}", message.fetch("Text"))
  end

  def test_custom_mail_headers
    override_config({
      "web" => {
        "mailer" => {
          "headers" => {
            "X-Foo" => unique_test_id,
          },
        },
      },
    }) do
      response = Typhoeus.post("https://127.0.0.1:9081/api-umbrella/v1/users.json", http_options.deep_merge(non_admin_key_creator_api_key).deep_merge({
        :headers => { "Content-Type" => "application/x-www-form-urlencoded" },
        :body => {
          :user => FactoryBot.attributes_for(:api_user),
          :options => { :send_welcome_email => true },
        },
      }))
      assert_response_code(201, response)

      messages = sent_email_contents
      assert_equal(1, messages.fetch("total"))
      message = messages.fetch("messages").first

      assert_equal([unique_test_id], message.fetch("headers").fetch("X-Foo"))
    end
  end

  private

  def non_admin_key_creator_api_key
    user = FactoryBot.create(:api_user, {
      :roles => ["api-umbrella-key-creator"],
    })

    { :headers => { "X-Api-Key" => user.api_key } }
  end
end

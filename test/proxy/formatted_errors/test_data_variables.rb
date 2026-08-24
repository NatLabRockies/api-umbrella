require_relative "../../test_helper"

class Test::Proxy::FormattedErrors::TestDataVariables < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::FormattedErrors

  parallelize_me!

  def setup
    super
    setup_server
    once_per_class_setup do
      @@escape_test_value = "'\"&><,\\"
      prepend_api_backends([
        {
          :frontend_host => "127.0.0.1",
          :backend_host => "example.com",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/#{unique_test_class_id}/", :backend_prefix => "/" }],
          :settings => {
            :error_data => {
              :api_key_missing => {
                :embedded => "base_url: {{base_url}} signup_url: {{signup_url}} contact_url: {{contact_url}}",
                :embedded_legacy => "baseUrl: {{baseUrl}} signupUrl: {{signupUrl}} contactUrl: {{contactUrl}}",
                :escape_test => @@escape_test_value,
              },
            },
            :error_templates => {
              :json => <<~EOS,
                {
                  "error": {
                    "code": {{code}}
                  },
                  "base_url": {{base_url}},
                  "baseUrl": {{baseUrl}},
                  "signup_url": {{signup_url}},
                  "signupUrl": {{signupUrl}},
                  "contact_url": {{contact_url}},
                  "contactUrl": {{contactUrl}},
                  "embedded": {{embedded}},
                  "embedded_legacy": {{embedded_legacy}},
                  "escape_test": {{escape_test}}
                }
              EOS
              :xml => <<~EOS,
                <?xml version="1.0" encoding="UTF-8"?>
                <response>
                  <error>
                    <code>{{code}}</code>
                    <message>{{message}}</message>
                    <escape-test>{{escape_test}}</escape-test>
                  </error>
                </response>
              EOS
              :csv => <<~EOS,
                Error Code,Error Message
                {{code}},{{message}},{{escape_test}}
              EOS
              :html => <<~EOS,
                <html>
                  <body>
                    <h1>{{code}}</h1>
                    <p>{{escape_test}}</p>
                  </body>
                </html>
              EOS
            },
          },
        },
      ])
    end
  end

  def test_variables
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", keyless_http_options)
    assert_json_error(response)
    data = MultiJson.load(response.body)
    assert_equal("http://127.0.0.1:9080", data["base_url"])
    assert_equal("http://127.0.0.1:9080", data["signup_url"])
    assert_equal("http://127.0.0.1:9080", data["contact_url"])
  end

  def test_legacy_camel_case
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", keyless_http_options)
    assert_json_error(response)
    data = MultiJson.load(response.body)
    assert_equal("http://127.0.0.1:9080", data["baseUrl"])
    assert_equal("http://127.0.0.1:9080", data["signupUrl"])
    assert_equal("http://127.0.0.1:9080", data["contactUrl"])
  end

  def test_variables_inside_other_variables
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", keyless_http_options)
    assert_json_error(response)
    data = MultiJson.load(response.body)
    assert_equal("base_url: http://127.0.0.1:9080 signup_url: http://127.0.0.1:9080 contact_url: http://127.0.0.1:9080", data["embedded"])
  end

  def test_legacy_camel_case_variables_inside_other_variables
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello", keyless_http_options)
    assert_json_error(response)
    data = MultiJson.load(response.body)
    assert_equal("baseUrl: http://127.0.0.1:9080 signupUrl: http://127.0.0.1:9080 contactUrl: http://127.0.0.1:9080", data["embedded_legacy"])
  end

  def test_escapes_json_values
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello.json", keyless_http_options)
    assert_json_error(response)
    data = MultiJson.load(response.body)
    assert(@@escape_test_value)
    assert_equal(@@escape_test_value, data["escape_test"])
  end

  def test_escapes_xml_values
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello.xml", keyless_http_options)
    assert_xml_error(response)
    doc = REXML::Document.new(response.body)
    assert(@@escape_test_value)
    assert_equal(@@escape_test_value, doc.elements["/response/error/escape-test"].text)
  end

  def test_escapes_html_values
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello.html", keyless_http_options)
    assert_html_error(response)
    doc = REXML::Document.new(response.body)
    assert(@@escape_test_value)
    assert_equal(@@escape_test_value, doc.elements["/html/body/p"].text)
  end

  def test_escapes_csv_values
    response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_class_id}/hello.csv", keyless_http_options)
    assert_csv_error(response)
    data = CSV.parse(response.body)
    assert(@@escape_test_value)
    assert_equal(@@escape_test_value, data[1][2])
  end

  def test_merges_custom_varaibles_with_default_variables
    prepend_api_backends([
      {
        :frontend_host => "127.0.0.1",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
        :settings => {
          :error_templates => {
            :json => '{ "code": {{code}}, "message": {{message}}, "custom": "custom hello", "newvar": {{newvar}}, "signup_url": {{signup_url}}, "contact_url": {{contact_url}} }',
          },
          :error_data => {
            :common => {
              :contact_url => "https://example.com/common-var-override",
            },
            :api_key_missing => {
              :newvar => "foo",
              :message => "new message",
            },
          },
        },
      },
    ]) do
      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/hello.json", keyless_http_options)
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal("API_KEY_MISSING", data["code"])
      assert_equal("new message", data["message"])
      assert_equal("foo", data["newvar"])
      assert_equal("custom hello", data["custom"])
      assert_equal("http://127.0.0.1:9080", data["signup_url"])
      assert_equal("https://example.com/common-var-override", data["contact_url"])
    end
  end

  def test_empty_sub_url_settings_inherits_parent_settings
    prepend_api_backends([
      {
        :frontend_host => "127.0.0.1",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
        :settings => {
          :error_data => {
            :common => {
              :signup_url => "https://example.com/testing-sub-settings-signup",
            },
          },
        },
        :sub_settings => [
          {
            :http_method => "any",
            :regex => "^/hello/sub-inherit/",
            :settings => {
              :error_data => {},
            },
          },
        ],
      },
    ]) do
      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/", keyless_http_options)
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal("API_KEY_MISSING", data.fetch("error").fetch("code"))
      assert_equal("No api_key was supplied. Get one at https://example.com/testing-sub-settings-signup", data.fetch("error").fetch("message"))

      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/hello/sub-inherit/", keyless_http_options)
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal("API_KEY_MISSING", data.fetch("error").fetch("code"))
      assert_equal("No api_key was supplied. Get one at https://example.com/testing-sub-settings-signup", data.fetch("error").fetch("message"))
    end
  end

  def test_empty_settings_and_sub_url_settings_inherits_default
    prepend_api_backends([
      {
        :frontend_host => "127.0.0.1",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
        :settings => {
          :error_data => {},
        },
        :sub_settings => [
          {
            :http_method => "any",
            :regex => "^/hello/sub-inherit/",
            :settings => {
              :error_data => {},
            },
          },
        ],
      },
    ]) do
      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/", keyless_http_options)
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal("API_KEY_MISSING", data.fetch("error").fetch("code"))
      assert_equal("No api_key was supplied. Get one at http://127.0.0.1:9080", data.fetch("error").fetch("message"))

      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/hello/sub-inherit/", keyless_http_options)
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal("API_KEY_MISSING", data.fetch("error").fetch("code"))
      assert_equal("No api_key was supplied. Get one at http://127.0.0.1:9080", data.fetch("error").fetch("message"))
    end
  end

  def test_sub_url_settings_overrides_parent_settings
    prepend_api_backends([
      {
        :frontend_host => "127.0.0.1",
        :backend_host => "127.0.0.1",
        :servers => [{ :host => "127.0.0.1", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/", :backend_prefix => "/" }],
        :settings => {
          :error_templates => {
            :json => '{ "error": { "code": {{code}}, "message": {{message}}, "signup_url": {{signup_url}}, "contact_url": {{contact_url}} } }',
          },
          :error_data => {
            :common => {
              :signup_url => "https://example.com/testing-sub-settings-signup",
              :contact_url => "https://example.com/testing-sub-settings-contact",
            },
          },
        },
        :sub_settings => [
          {
            :http_method => "any",
            :regex => "^/hello/sub-merge/",
            :settings => {
              :error_data => {
                :common => {
                  :signup_url => "https://example.com/testing-sub-settings-signup-override",
                },
              },
            },
          },
        ],
      },
    ]) do
      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/", keyless_http_options)
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal("API_KEY_MISSING", data.fetch("error").fetch("code"))
      assert_equal("No api_key was supplied. Get one at https://example.com/testing-sub-settings-signup", data.fetch("error").fetch("message"))
      assert_equal("https://example.com/testing-sub-settings-signup", data.fetch("error").fetch("signup_url"))
      assert_equal("https://example.com/testing-sub-settings-contact", data.fetch("error").fetch("contact_url"))

      response = Typhoeus.get("http://127.0.0.1:9080/#{unique_test_id}/hello/sub-merge/", keyless_http_options)
      assert_response_code(403, response)
      assert_equal("application/json", response.headers["content-type"])
      data = MultiJson.load(response.body)
      assert_equal("API_KEY_MISSING", data.fetch("error").fetch("code"))
      assert_equal("No api_key was supplied. Get one at https://example.com/testing-sub-settings-signup-override", data.fetch("error").fetch("message"))
      assert_equal("https://example.com/testing-sub-settings-signup-override", data.fetch("error").fetch("signup_url"))
      assert_equal("https://example.com/testing-sub-settings-contact", data.fetch("error").fetch("contact_url"))
    end
  end
end

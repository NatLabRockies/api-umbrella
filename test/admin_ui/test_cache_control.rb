require_relative "../test_helper"

class Test::AdminUi::TestCacheControl < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  parallelize_me!

  def setup
    super
    setup_server
  end

  def test_admin_ui
    # Check the admin index.html
    response = Typhoeus.get("https://127.0.0.1:9081/admin/", keyless_http_options)
    assert_response_code(200, response)
    assert_equal("text/html", response.headers["Content-Type"])
    assert_equal("no-cache, max-age=0, must-revalidate, no-store", response.headers["Cache-Control"])
    assert_equal("no-cache", response.headers["Pragma"])

    # Parse the HTML page and find the JS and CSS assets.
    doc = Nokogiri::HTML(response.body)
    scripts = doc.xpath("//body//script[starts-with(@src, '/admin/assets/')]")
    assert_operator(scripts.length, :>=, 1)
    stylesheets = doc.xpath("//head//link[starts-with(@href, '/admin/assets/')]")
    assert_operator(stylesheets.length, :>=, 1)

    # Ensure that all the linked assets use fingerprinted filenames (for cache
    # busting), and return long cache-control headers.
    scripts.each do |script|
      assert_match(%r{\A/admin/assets/([\w-]+-\w{32}|chunk\.\d+\.\w{20})\.js\z}, script[:src])

      response = Typhoeus.get("https://127.0.0.1:9081#{script[:src]}", keyless_http_options)
      assert_response_code(200, response)
      assert_equal("application/javascript", response.headers["Content-Type"])
      assert_equal("public, max-age=31536000, immutable", response.headers["Cache-Control"])
      assert_nil(response.headers["Pragma"])
    end
    stylesheets.each do |stylesheet|
      assert_match(%r{\A/admin/assets/([\w-]+-\w{32}|chunk\.\d+\.\w{20})\.css\z}, stylesheet[:href])

      response = Typhoeus.get("https://127.0.0.1:9081#{stylesheet[:href]}", keyless_http_options)
      assert_response_code(200, response)
      assert_equal("text/css", response.headers["Content-Type"])
      assert_equal("public, max-age=31536000, immutable", response.headers["Cache-Control"])
      assert_nil(response.headers["Pragma"])
    end
  end

  def test_admin_login
    # Check the server-side page.
    FactoryBot.create(:admin)
    response = Typhoeus.get("https://127.0.0.1:9081/admin/login", keyless_http_options)
    assert_response_code(200, response)
    assert_equal("text/html", response.headers["Content-Type"])
    assert_equal("no-cache, max-age=0, must-revalidate, no-store", response.headers["Cache-Control"])
    assert_equal("no-cache", response.headers["Pragma"])

    # Parse the HTML page and find the CSS assets.
    doc = Nokogiri::HTML(response.body)
    stylesheets = doc.xpath("//head//link[starts-with(@href, '/web-assets/')]")
    assert_equal(1, stylesheets.length)

    # Ensure that all the linked assets use fingerprinted filenames (for cache
    # busting), and return long cache-control headers.
    stylesheets.each do |stylesheet|
      assert_match(%r{\A/web-assets/assets/[\w-]+-\w{8}\.css\z}, stylesheet[:href])

      response = Typhoeus.get("https://127.0.0.1:9081#{stylesheet[:href]}", keyless_http_options)
      assert_response_code(200, response)
      assert_equal("text/css", response.headers["Content-Type"])
      assert_equal("public, max-age=31536000, immutable", response.headers["Cache-Control"])
      assert_nil(response.headers["Pragma"])
    end
  end

  def test_server_side_loader
    response = Typhoeus.get("https://127.0.0.1:9081/admin/server_side_loader.js", keyless_http_options)
    assert_response_code(200, response)
    assert_equal("application/javascript", response.headers["Content-Type"])
    assert_equal("no-cache, max-age=0, must-revalidate, no-store", response.headers["Cache-Control"])
    assert_equal("no-cache", response.headers["Pragma"])
  end

  def test_admin_api
    response = Typhoeus.get("https://127.0.0.1:9081/api-umbrella/v1/apis.json", http_options.deep_merge(admin_token))
    assert_response_code(200, response)
    assert_equal("application/json; charset=utf-8", response.headers["Content-Type"])
    assert_equal("no-cache, max-age=0, must-revalidate, no-store", response.headers["Cache-Control"])
    assert_equal("no-cache", response.headers["Pragma"])
  end
end

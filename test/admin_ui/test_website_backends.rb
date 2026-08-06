require_relative "../test_helper"

class Test::AdminUi::TestWebsiteBackends < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_duplicate_creates_new_record_with_copied_data
    source = FactoryBot.create(:website_backend, :frontend_host => "source.example.com", :server_host => "backend.example.com", :server_port => 8080)
    source_id = source.id
    source_frontend_host = source.frontend_host
    source_server_host = source.server_host
    source_server_port = source.server_port

    admin_login
    visit "/admin/#/website_backends/#{source.id}/edit"
    assert_field("Frontend Host", :with => "source.example.com")

    find("a.duplicate-action", :text => /Duplicate Website Backend/).click

    assert_current_path %r{/admin/#/website_backends/new\?duplicate_id=#{source.id}}, :url => true
    assert_text("Duplicated from")
    assert_field("Frontend Host", :with => "source.example.com")
    assert_field("Backend Server", :with => "backend.example.com")
    assert_field("Backend Port", :with => "8080")

    fill_in("Frontend Host", :with => "duplicate.example.com")
    click_button("Save")
    assert_text("Successfully saved")

    duplicate = WebsiteBackend.where(:frontend_host => "duplicate.example.com").order(:created_at => :desc).first
    refute_nil(duplicate, "duplicate website-backend was created")
    refute_equal(source_id, duplicate.id, "duplicate has fresh id")
    assert_equal(source_server_host, duplicate.server_host, "server_host preserved")
    assert_equal(source_server_port, duplicate.server_port, "server_port preserved")

    source.reload
    assert_equal(source_frontend_host, source.frontend_host, "source frontend_host unchanged")
  end

  def test_duplicate_link_hidden_on_new_form
    admin_login
    visit "/admin/#/website_backends/new"
    assert_field("Frontend Host")
    refute_selector("a.duplicate-action")
  end
end

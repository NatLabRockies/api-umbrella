require_relative "../test_helper"

class Test::AdminUi::TestApiScopes < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_create
    admin_login
    visit("/admin/#/api_scopes/new")

    fill_in("Name", :with => "Example")
    fill_in("Host", :with => "example.com")
    fill_in("Path Prefix", :with => "/foo/")

    click_button("Save")
    assert_text("Successfully saved")

    api_scope = ApiScope.order(:created_at => :desc).first
    assert_equal("Example", api_scope.name)
    assert_equal("example.com", api_scope.host)
    assert_equal("/foo/", api_scope.path_prefix)
  end

  def test_update
    api_scope = FactoryBot.create(:api_scope, :name => "Example", :path_prefix => "/example")

    admin_login
    visit("/admin/#/api_scopes/#{api_scope.id}/edit")

    assert_field("Name", :with => "Example")
    assert_field("Host", :with => "localhost")
    assert_field("Path Prefix", :with => "/example")

    fill_in("Name", :with => "Example2")
    fill_in("Host", :with => "2.example.com")
    fill_in("Path Prefix", :with => "/2/")

    click_button("Save")
    assert_text("Successfully saved")

    api_scope.reload
    assert_equal("Example2", api_scope.name)
    assert_equal("2.example.com", api_scope.host)
    assert_equal("/2/", api_scope.path_prefix)
  end

  def test_duplicate_creates_new_record_with_path_prefix_cleared
    source = FactoryBot.create(:api_scope, :name => "Source Scope For Duplicate", :host => "source.example.com", :path_prefix => "/source/")
    source_id = source.id
    source_host = source.host
    source_path_prefix = source.path_prefix

    admin_login
    visit "/admin/#/api_scopes/#{source.id}/edit"
    assert_field("Name", :with => "Source Scope For Duplicate")

    find("a.duplicate-action", :text => /Duplicate API Scope/).click

    assert_current_path %r{/admin/#/api_scopes/new\?duplicate_id=#{source.id}}, :url => true
    assert_text("Duplicated from Source Scope For Duplicate")
    assert_field("Name", :with => "Source Scope For Duplicate")
    assert_field("Host", :with => "source.example.com")
    assert_field("Path Prefix", :with => "")

    fill_in("Name", :with => "Duplicate Scope For Duplicate")
    fill_in("Path Prefix", :with => "/duplicate/")
    click_button("Save")
    assert_text("Successfully saved")

    duplicate = ApiScope.where(:name => "Duplicate Scope For Duplicate").order(:created_at => :desc).first
    refute_nil(duplicate, "duplicate scope was created")
    refute_equal(source_id, duplicate.id, "duplicate has fresh id")
    assert_equal(source_host, duplicate.host, "host preserved")
    assert_equal("/duplicate/", duplicate.path_prefix, "duplicate has new path_prefix")

    source.reload
    assert_equal("Source Scope For Duplicate", source.name, "source name unchanged")
    assert_equal(source_path_prefix, source.path_prefix, "source path_prefix unchanged")
  end

  def test_duplicate_link_hidden_on_new_form
    admin_login
    visit "/admin/#/api_scopes/new"
    assert_field("Name")
    refute_selector("a.duplicate-action")
  end
end

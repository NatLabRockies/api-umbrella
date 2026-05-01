require_relative "../test_helper"

class Test::AdminUi::TestAdminGroups < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_create
    api_scope = FactoryBot.create(:api_scope, :name => "Example Scope")

    admin_login
    visit("/admin/#/admin_groups/new")

    fill_in("Group Name", :with => "Example")
    check("Example Scope")
    check("Analytics")

    click_button("Save")
    assert_text("Successfully saved")

    admin_group = AdminGroup.order(:created_at => :desc).first
    assert_equal("Example", admin_group.name)
    assert_equal([api_scope.id], admin_group.api_scope_ids)
    assert_equal(["analytics"], admin_group.permission_ids)
  end

  def test_update
    api_scope1 = FactoryBot.create(:api_scope, :name => "Example Scope 1")
    api_scope2 = FactoryBot.create(:api_scope, :name => "Example Scope 2")
    admin_group = FactoryBot.create(:admin_group, {
      :name => "Example",
      :api_scopes => [api_scope1],
    })

    admin_login
    visit("/admin/#/admin_groups/#{admin_group.id}/edit")

    assert_field("Group Name", :with => "Example")
    assert_checked_field("Example Scope 1", :visible => :all)
    assert_unchecked_field("Example Scope 2", :visible => :all)
    assert_checked_field("Analytics", :visible => :all)
    assert_checked_field("API Users - View", :visible => :all)
    assert_checked_field("API Users - Manage", :visible => :all)
    assert_checked_field("Admin Accounts - View", :visible => :all)
    assert_checked_field("Admin Accounts - Manage", :visible => :all)
    assert_checked_field("API Backend Configuration - View & Manage", :visible => :all)
    assert_checked_field("API Backend Configuration - Publish", :visible => :all)

    fill_in("Group Name", :with => "Example2")
    uncheck("Example Scope 1")
    check("Example Scope 2")
    uncheck("API Backend Configuration - Publish")

    click_button("Save")
    assert_text("Successfully saved")

    admin_group.reload
    assert_equal("Example2", admin_group.name)
    assert_equal([api_scope2.id], admin_group.api_scope_ids)
    assert_equal([
      "analytics",
      "user_view",
      "user_manage",
      "admin_view",
      "admin_manage",
      "backend_manage",
    ].sort, admin_group.permission_ids.sort)
  end

  def test_duplicate_creates_new_record_with_copied_data
    api_scope = FactoryBot.create(:api_scope, :name => "Scope For Duplicate")
    source = FactoryBot.create(:admin_group, :name => "Source Group For Duplicate", :api_scopes => [api_scope])
    source_id = source.id
    source_api_scope_ids = source.api_scope_ids.sort
    source_permission_ids = source.permission_ids.sort

    admin_login
    visit "/admin/#/admin_groups/#{source.id}/edit"
    assert_field("Group Name", :with => "Source Group For Duplicate")

    find("a.duplicate-action", :text => /Duplicate Admin Group/).click

    assert_current_path %r{/admin/#/admin_groups/new\?duplicate_id=#{source.id}}, :url => true
    assert_text("Duplicated from Source Group For Duplicate")
    assert_field("Group Name", :with => "Source Group For Duplicate")
    assert_checked_field("Scope For Duplicate", :visible => :all)

    fill_in("Group Name", :with => "Duplicate Group For Duplicate")
    click_button("Save")
    assert_text("Successfully saved")

    duplicate = AdminGroup.where(:name => "Duplicate Group For Duplicate").order(:created_at => :desc).first
    refute_nil(duplicate, "duplicate group was created")
    refute_equal(source_id, duplicate.id, "duplicate has fresh id")
    assert_equal(source_api_scope_ids, duplicate.api_scope_ids.sort, "duplicate references same scopes as source")
    assert_equal(source_permission_ids, duplicate.permission_ids.sort, "duplicate references same permissions as source")

    source.reload
    assert_equal("Source Group For Duplicate", source.name, "source name unchanged")
    assert_equal(source_api_scope_ids, source.api_scope_ids.sort, "source scopes unchanged")
  end
end

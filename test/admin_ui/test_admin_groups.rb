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

  def test_delete_shows_success_notification_and_no_error
    admin_group = FactoryBot.create(:admin_group, :name => "Delete Me Group")

    admin_login
    visit "/admin/#/admin_groups/#{admin_group.id}/edit"
    assert_field("Group Name", :with => "Delete Me Group")

    find("a.remove-action", :text => /Delete Admin Group/).click
    click_button("OK")

    assert_text("Successfully deleted")
    refute_text("Unexpected error deleting record")

    assert_nil(AdminGroup.where(:id => admin_group.id).first)
  end
end

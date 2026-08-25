require_relative "../test_helper"

class Test::AdminUi::TestAdmins < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_superuser_checkbox_as_superuser_admin
    admin_login
    visit "/admin/#/admins/new"

    assert_text("Email")
    assert_text("Superuser")
  end

  def test_superuser_checkbox_as_limited_admin
    admin_login(FactoryBot.create(:limited_admin))
    visit "/admin/#/admins/new"

    assert_text("Email")
    refute_text("Superuser")
  end

  def test_adds_groups_when_checked
    admin_login

    @group1 = FactoryBot.create(:admin_group)
    @group2 = FactoryBot.create(:admin_group)
    @group3 = FactoryBot.create(:admin_group)

    admin = FactoryBot.create(:admin)
    assert_equal([], admin.group_ids)

    visit "/admin/#/admins/#{admin.id}/edit"

    check @group1.name
    check @group3.name

    click_button("Save")

    assert_text("Successfully saved the admin")

    admin = Admin.find(admin.id)
    assert_equal([@group1.id, @group3.id].sort, admin.group_ids.sort)
  end

  def test_removes_groups_when_checked
    admin_login

    @group1 = FactoryBot.create(:admin_group)
    @group2 = FactoryBot.create(:admin_group)
    @group3 = FactoryBot.create(:admin_group)

    admin = FactoryBot.create(:admin, :groups => [@group1, @group2])
    assert_equal([@group1.id, @group2.id].sort, admin.group_ids.sort)

    visit "/admin/#/admins/#{admin.id}/edit"

    uncheck @group1.name
    uncheck @group2.name
    check @group3.name

    click_button("Save")

    assert_text("Successfully saved the admin")

    admin = Admin.find(admin.id)
    assert_equal([@group3.id].sort, admin.group_ids.sort)
  end

  def test_non_admin_manager_views_own_profile
    # An admin without the "admin_manage" role.
    admin = FactoryBot.create(:limited_admin, :groups => [
      FactoryBot.create(:google_admin_group, :analytics_permission),
    ])
    admin_login(admin)

    visit "/admin/#/admins/#{admin.id}/edit"

    refute_field("Email")
    assert_text("Email")
    assert_text(admin.username)
    refute_field("Notes")
    refute_text("Notes")
    assert_text("Change Your Password")
    assert_field("Current Password")
    assert_field("New Password")
    refute_text("Permissions")
    assert_text("Admin API Access")
    assert_text("Admin API Token")
    assert(admin.authentication_token)
    assert_text(admin.authentication_token)
    assert_button("Save")
  end
end

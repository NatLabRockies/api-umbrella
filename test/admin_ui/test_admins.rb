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
    # TODO: Admins should be able to set their own password, even if they lack
    # the admin_manage role.
    refute_text("Change Your Password")
    refute_field("Current Password")
    refute_field("New Password")
    refute_text("Permissions")
    assert_text("Admin API Access")
    assert_text("Admin API Token")
    assert(admin.authentication_token)
    assert_text(admin.authentication_token)
    refute_button("Save")
  end

  def test_duplicate_creates_new_record_with_email_cleared
    group = FactoryBot.create(:admin_group, :name => "Group For Duplicate")
    source = FactoryBot.create(:limited_admin, :username => "source.admin@example.com", :groups => [group])
    source_id = source.id
    source_username = source.username
    source_email = source.email
    source_group_ids = source.group_ids.sort

    admin_login
    visit "/admin/#/admins/#{source.id}/edit"
    assert_field("Email", :with => "source.admin@example.com")

    find("a.duplicate-action", :text => /Duplicate Admin/).click

    assert_current_path %r{/admin/#/admins/new\?duplicate_id=#{source.id}}, :url => true
    assert_text("Duplicated from")
    assert_field("Email", :with => "")

    fill_in("Email", :with => "duplicate.admin@example.com")
    click_button("Save")
    assert_text("Successfully saved the admin")

    duplicate = Admin.where(:username => "duplicate.admin@example.com").order(:created_at => :desc).first
    refute_nil(duplicate, "duplicate admin was created")
    refute_equal(source_id, duplicate.id, "duplicate has fresh id")
    refute_equal(source_username, duplicate.username, "duplicate has fresh username")
    refute_equal(source_email, duplicate.email, "duplicate has fresh email")
    assert_equal(source_group_ids, duplicate.group_ids.sort, "duplicate references same groups as source")

    source.reload
    assert_equal(source_username, source.username, "source username unchanged")
    assert_equal(source_email, source.email, "source email unchanged")
  end

  def test_duplicate_link_hidden_on_new_form
    admin_login
    visit "/admin/#/admins/new"
    assert_text("Email")
    refute_selector("a.duplicate-action")
  end
end

require_relative "../test_helper"

class Test::AdminUi::TestApisNestedReordering < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
  end

  def test_reordering_nested_associations
    admin_login
    visit "/admin/#/apis/new"

    fill_in "Name", :with => "Testing API Backend"

    # Backend
    select "https", :from => "Backend Protocol"
    find("button", :text => /Add Server/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      fill_in "Host", :with => "google.com"
      assert_field("Port", :with => "443")
      click_button("OK")
    end
    refute_selector ".modal-content"

    # Host
    fill_in "Frontend Host", :with => "api.foo.com"
    fill_in "Backend Host", :with => "api.bar.com"

    # Matching URL Prefixes
    find("button", :text => /Add URL Prefix/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      fill_in "Frontend Prefix", :with => "/foo"
      fill_in "Backend Prefix", :with => "/foo"
      click_button("OK")
    end
    refute_selector ".modal-content"
    find("button", :text => /Add URL Prefix/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      fill_in "Frontend Prefix", :with => "/bar"
      fill_in "Backend Prefix", :with => "/bar"
      click_button("OK")
    end
    refute_selector ".modal-content"

    # Sub-URL Request Settings
    find("legend button", :text => /Sub-URL Request Settings/).click
    find("button", :text => /Add URL Settings/).click
    assert_selector(".modal-content")
    refute_selector "#sub_settings_table_reorder"
    within(".modal-content") do
      select "OPTIONS", :from => "HTTP Method"
      fill_in "Regex", :with => "^/foo.*"
      click_button("OK")
    end
    refute_selector ".modal-content"
    refute_selector "#sub_settings_table_reorder"
    find("button", :text => /Add URL Settings/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      select "OPTIONS", :from => "HTTP Method"
      fill_in "Regex", :with => "^/bar.*"
      click_button("OK")
    end
    refute_selector ".modal-content"
    assert_selector "#sub_settings_table_reorder"

    # Advanced Requests Rewriting
    find("legend button", :text => /Advanced Requests Rewriting/).click
    find("button", :text => /Add Rewrite/).click
    assert_selector(".modal-content")
    refute_selector "#rewrites_table_reorder"
    within(".modal-content") do
      select "Regular Expression", :from => "Matcher Type"
      select "PUT", :from => "HTTP Method"
      fill_in "Frontend Matcher", :with => "foo"
      fill_in "Backend Replacement", :with => "foo"
      click_button("OK")
    end
    refute_selector ".modal-content"
    refute_selector "#rewrites_table_reorder"
    find("button", :text => /Add Rewrite/).click
    assert_selector(".modal-content")
    within(".modal-content") do
      select "Regular Expression", :from => "Matcher Type"
      select "PUT", :from => "HTTP Method"
      fill_in "Frontend Matcher", :with => "bar"
      fill_in "Backend Replacement", :with => "bar"
      click_button("OK")
    end
    refute_selector ".modal-content"
    assert_selector "#rewrites_table_reorder"

    click_button("Save")
    assert_text("Successfully saved")

    # Verify that the initial save had the expected sort order.
    api = ApiBackend.order(:created_at => :desc).first

    assert_equal("^/foo.*", api.sub_settings[0].regex)
    assert_equal(1, api.sub_settings[0].sort_order)
    assert_equal("^/bar.*", api.sub_settings[1].regex)
    assert_equal(2, api.sub_settings[1].sort_order)

    assert_equal("foo", api.rewrites[0].frontend_matcher)
    assert_equal(1, api.rewrites[0].sort_order)
    assert_equal("bar", api.rewrites[1].frontend_matcher)
    assert_equal(2, api.rewrites[1].sort_order)

    # Make an edit unrelated to the nested associations to ensure their sort
    # order doesn't change.
    visit "/admin/#/apis/#{api.id}/edit"

    fill_in "Name", :with => "Testing API Backend Update"
    click_button("Save")
    assert_text("Successfully saved")

    api.reload

    assert_equal("^/foo.*", api.sub_settings[0].regex)
    assert_equal(1, api.sub_settings[0].sort_order)
    assert_equal("^/bar.*", api.sub_settings[1].regex)
    assert_equal(2, api.sub_settings[1].sort_order)

    assert_equal("foo", api.rewrites[0].frontend_matcher)
    assert_equal(1, api.rewrites[0].sort_order)
    assert_equal("bar", api.rewrites[1].frontend_matcher)
    assert_equal(2, api.rewrites[1].sort_order)

    # Reorder the nested associations.
    visit "/admin/#/apis/#{api.id}/edit"

    find("legend button", :text => /Sub-URL Request Settings/).click
    within("#sub_settings_table tbody tr:nth-child(1)") do
      assert_text("^/foo.*")
    end
    within("#sub_settings_table tbody tr:nth-child(2)") do
      assert_text("^/bar.*")
    end
    click_button "sub_settings_table_reorder"
    assert_selector("#sub_settings_table tbody tr:nth-child(1) td:nth-child(2)", :text => "^/foo.*")
    handle = find("#sub_settings_table tbody tr:nth-child(2) td:nth-child(2)", :text => "^/bar.*").find(:xpath, "..").find(".reorder-handle")
    target = find("#sub_settings_table tbody tr:nth-child(1)")
    handle.drag_to(target)
    assert_selector("#sub_settings_table tbody tr:nth-child(1) td:nth-child(2)", :text => "^/bar.*")

    find("legend button", :text => /Advanced Requests Rewriting/).click
    within("#rewrites_table tbody tr:nth-child(1)") do
      assert_text("foo")
    end
    within("#rewrites_table tbody tr:nth-child(2)") do
      assert_text("bar")
    end
    click_button "rewrites_table_reorder"
    assert_selector("#rewrites_table tbody tr:nth-child(1) td:nth-child(3)", :text => "foo")
    handle = find("#rewrites_table tbody tr:nth-child(2) td:nth-child(3)", :text => "bar").find(:xpath, "..").find(".reorder-handle")
    target = find("#rewrites_table tbody tr:nth-child(1)")
    handle.drag_to(target)
    assert_selector("#rewrites_table tbody tr:nth-child(1) td:nth-child(3)", :text => "bar")

    click_button("Save")
    assert_text("Successfully saved")

    api.reload

    assert_equal("^/bar.*", api.sub_settings[0].regex)
    assert_equal(1, api.sub_settings[0].sort_order)
    assert_equal("^/foo.*", api.sub_settings[1].regex)
    assert_equal(2, api.sub_settings[1].sort_order)

    assert_equal("bar", api.rewrites[0].frontend_matcher)
    assert_equal(1, api.rewrites[0].sort_order)
    assert_equal("foo", api.rewrites[1].frontend_matcher)
    assert_equal(2, api.rewrites[1].sort_order)

    # Verify the tables render in the correct order after the changes.
    visit "/admin/#/apis/#{api.id}/edit"

    find("legend button", :text => /Sub-URL Request Settings/).click
    within("#sub_settings_table tbody tr:nth-child(1)") do
      assert_text("^/bar.*")
    end
    within("#sub_settings_table tbody tr:nth-child(2)") do
      assert_text("^/foo.*")
    end

    find("legend button", :text => /Advanced Requests Rewriting/).click
    within("#rewrites_table tbody tr:nth-child(1)") do
      assert_text("bar")
    end
    within("#rewrites_table tbody tr:nth-child(2)") do
      assert_text("foo")
    end

    # Verify that when already in reorder mode if new table rows are added,
    # then the new rows are also reorderable.
    click_button "sub_settings_table_reorder"
    click_button "rewrites_table_reorder"
    find("button", :text => /Add URL Settings/).click
    within(".modal-content") do
      select "OPTIONS", :from => "HTTP Method"
      fill_in "Regex", :with => "^/baz.*"
      click_button("OK")
    end
    refute_selector ".modal-content"
    find("button", :text => /Add Rewrite/).click
    within(".modal-content") do
      select "Regular Expression", :from => "Matcher Type"
      select "PUT", :from => "HTTP Method"
      fill_in "Frontend Matcher", :with => "baz"
      fill_in "Backend Replacement", :with => "baz"
      click_button("OK")
    end
    refute_selector ".modal-content"
    handle = find("#sub_settings_table tbody tr:nth-child(3) td:nth-child(2)", :text => "^/baz.*").find(:xpath, "..").find(".reorder-handle")
    target = find("#sub_settings_table tbody tr:nth-child(2)")
    handle.drag_to(target)
    assert_selector("#sub_settings_table tbody tr:nth-child(2) td:nth-child(2)", :text => "^/baz.*")
    handle = find("#rewrites_table tbody tr:nth-child(3) td:nth-child(3)", :text => "baz").find(:xpath, "..").find(".reorder-handle")
    target = find("#rewrites_table tbody tr:nth-child(2)")
    handle.drag_to(target)
    assert_selector("#rewrites_table tbody tr:nth-child(2) td:nth-child(3)", :text => "baz")

    click_button("Save")
    assert_text("Successfully saved")

    api.reload

    assert_equal("^/bar.*", api.sub_settings[0].regex)
    assert_equal(1, api.sub_settings[0].sort_order)
    assert_equal("^/baz.*", api.sub_settings[1].regex)
    assert_equal(2, api.sub_settings[1].sort_order)
    assert_equal("^/foo.*", api.sub_settings[2].regex)
    assert_equal(3, api.sub_settings[2].sort_order)

    assert_equal("bar", api.rewrites[0].frontend_matcher)
    assert_equal(1, api.rewrites[0].sort_order)
    assert_equal("baz", api.rewrites[1].frontend_matcher)
    assert_equal(2, api.rewrites[1].sort_order)
    assert_equal("foo", api.rewrites[2].frontend_matcher)
    assert_equal(3, api.rewrites[2].sort_order)
  end
end

require_relative "../test_helper"

class Test::AdminUi::TestStatsLogs < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::DateRangePicker
  include ApiUmbrellaTestHelpers::Downloads
  include ApiUmbrellaTestHelpers::Setup

  DEFAULT_QUERY = JSON.generate({
    "condition" => "AND",
    "rules" => [{
      "field" => "gatekeeper_denied_code",
      "id" => "gatekeeper_denied_code",
      "input" => "select",
      "operator" => "is_null",
      "type" => "string",
      "value" => nil,
    }],
  })

  def setup
    super
    setup_server
    LogItem.clean_indices!
  end

  def test_xss_escaping_in_table
    log = FactoryBot.create(:xss_log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_method => "OPTIONS")
    LogItem.refresh_indices!

    admin_login
    visit "/admin/#/stats/logs?search=&start_at=2015-01-12&end_at=2015-01-18&interval=day"
    refute_selector(".busy-blocker")

    assert_text('"><script class="xss-test">alert(')
    refute_selector(".xss-test", :visible => :all)
    assert_text(log.api_backend_id)
    assert_text(log.api_backend_resolved_host)
    assert_text(log.api_backend_response_code_details)
    assert_text(log.api_backend_response_flags)
    assert_text(log.request_accept)
    assert_text(log.request_accept_encoding)
    assert_text(log.request_connection)
    assert_text(log.request_content_type)
    assert_text(log.request_host)
    assert_text(log.request_ip)
    assert_text(log.request_ip_city)
    assert_text(log.request_ip_country)
    assert_text(log.request_ip_region)
    assert_text(log.request_method)
    assert_text(log.request_origin)
    assert_text(log.request_path)
    assert_text(log.request_referer)
    assert_text(log.request_scheme)
    assert_text(log.request_url_query)
    assert_text(log.request_user_agent)
    assert_text(log.response_cache)
    assert_text(log.response_cache_flags)
    assert_text(log.response_content_encoding)
    assert_text(log.response_content_type)
    assert_text(log.response_custom1)
    assert_text(log.response_custom2)
    assert_text(log.response_custom3)
    assert_text(log.response_server)
    assert_text(log.response_transfer_encoding)
    assert_text(log.user_email)
    assert_text(log.user_id)
  end

  def test_csv_download_link_changes_with_filters
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc)
    LogItem.refresh_indices!

    admin_login
    visit "/admin/#/stats/logs?search=&start_at=2015-01-12&end_at=2015-01-18&interval=day"
    refute_selector(".busy-blocker")
    assert_link("Download CSV", :href => /start_at=2015-01-12/)
    link = find_link("Download CSV")
    uri = Addressable::URI.parse(link[:href])
    assert_equal("/admin/stats/logs.csv", uri.path)
    assert_equal({
      "search" => "",
      "start_at" => "2015-01-12",
      "end_at" => "2015-01-18",
      "interval" => "day",
      "query" => DEFAULT_QUERY,
    }, uri.query_values)

    visit "/admin/#/stats/logs?search=&start_at=2015-01-13&end_at=2015-01-18&interval=day"
    refute_selector(".busy-blocker")
    assert_link("Download CSV", :href => /start_at=2015-01-13/)
    link = find_link("Download CSV")
    uri = Addressable::URI.parse(link[:href])
    assert_equal("/admin/stats/logs.csv", uri.path)
    assert_equal({
      "search" => "",
      "start_at" => "2015-01-13",
      "end_at" => "2015-01-18",
      "interval" => "day",
      "query" => DEFAULT_QUERY,
    }, uri.query_values)

    visit "/admin/#/stats/logs?search=&start_at=2015-01-12&end_at=2015-01-18&interval=day"
    refute_selector(".busy-blocker")
    assert_link("Download CSV", :href => /start_at=2015-01-12/)
    assert_link("Download CSV", :href => /#{Regexp.escape(CGI.escape('"rules":[{'))}/)
    click_button "Delete" # Remove the initial filter
    click_button "Filter"
    refute_selector(".busy-blocker")
    assert_link("Download CSV", :href => /#{Regexp.escape(CGI.escape('"rules":[]'))}/)
    link = find_link("Download CSV")
    uri = Addressable::URI.parse(link[:href])
    assert_equal("/admin/stats/logs.csv", uri.path)
    assert_equal({
      "start_at" => "2015-01-12",
      "end_at" => "2015-01-18",
      "interval" => "day",
      "query" => JSON.generate({ "condition" => "AND", "rules" => [], "valid" => true }),
      "search" => "",
    }, uri.query_values)

    visit "/admin/#/stats/logs?search=&start_at=2015-01-13&end_at=2015-01-18&interval=day"
    refute_selector(".busy-blocker")
    assert_link("Download CSV", :href => /start_at=2015-01-13/)
    find("a", :text => /Switch to advanced filters/).click
    fill_in "search", :with => "response_status:200"
    click_button "Filter"
    refute_selector(".busy-blocker")
    assert_link("Download CSV", :href => /response_status%3A200/)
    link = find_link("Download CSV")
    uri = Addressable::URI.parse(link[:href])
    assert_equal("/admin/stats/logs.csv", uri.path)
    assert_equal({
      "search" => "response_status:200",
      "start_at" => "2015-01-13",
      "end_at" => "2015-01-18",
      "interval" => "day",
      "query" => "",
    }, uri.query_values)
  end

  def test_csv_download
    FactoryBot.create_list(:log_item, 5, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_method => "OPTIONS")
    FactoryBot.create_list(:log_item, 5, :request_at => 1421413588000, :request_method => "OPTIONS")
    LogItem.refresh_indices!

    admin_login
    visit "/admin/#/stats/logs?search=&start_at=2015-01-12&end_at=2015-01-18&interval=day"
    refute_selector(".busy-blocker")

    assert_link("Download CSV", :href => /start_at=2015-01-12/)
    link = find_link("Download CSV")
    uri = Addressable::URI.parse(link[:href])
    assert_equal("/admin/stats/logs.csv", uri.path)
    assert_equal({
      "search" => "",
      "start_at" => "2015-01-12",
      "end_at" => "2015-01-18",
      "interval" => "day",
      "query" => DEFAULT_QUERY,
    }, uri.query_values)

    # Wait for the ajax actions to fetch the graph and tables to both
    # complete, or else the download link seems to be flakey in Capybara.
    assert_text("Download CSV")
    assert_text("OPTIONS")
    refute_selector(".busy-blocker")
    click_link "Download CSV"

    file = download_file
    assert_equal(".csv", File.extname(file.path))
    csv = CSV.read(file.path)
    assert_equal([
      "Time",
      "Method",
      "Host",
      "URL",
      "User",
      "IP Address",
      "Country",
      "State",
      "City",
      "Status",
      "Reason Denied",
      "Response Time",
      "Content Type",
      "Accept Encoding",
      "User Agent",
      "User Agent Family",
      "User Agent Type",
      "Referer",
      "Origin",
      "Request Accept",
      "Request Connection",
      "Request Content Type",
      "Request Size",
      "Response Age",
      "Response Cache",
      "Response Cache Flags",
      "Response Content Encoding",
      "Response Content Length",
      "Response Server",
      "Response Size",
      "Response Transfer Encoding",
      "Response Custom Dimension 1",
      "Response Custom Dimension 2",
      "Response Custom Dimension 3",
      "User ID",
      "API Backend ID",
      "API Backend Resolved Host",
      "API Backend Response Code Details",
      "API Backend Response Flags",
      "Request ID",
    ], csv[0])
  end

  def test_changing_intervals
    admin_login
    visit "/admin/#/stats/logs?search=&start_at=2015-01-12&end_at=2015-01-13&interval=week"
    refute_selector(".busy-blocker")
    assert_selector("button.active", :text => "Week")
    assert_link("Download CSV", :href => /interval=week/)

    click_button "Day"
    refute_selector("button.active", :text => "Week")
    assert_selector("button.active", :text => "Day")
    assert_link("Download CSV", :href => /interval=day/)

    click_button "Hour"
    refute_selector("button.active", :text => "Day")
    assert_selector("button.active", :text => "Hour")
    assert_link("Download CSV", :href => /interval=hour/)

    click_button "Month"
    refute_selector("button.active", :text => "Hour")
    assert_selector("button.active", :text => "Month")
    assert_link("Download CSV", :href => /interval=month/)

    click_button "Minute"
    refute_selector("button.active", :text => "Month")
    assert_selector("button.active", :text => "Minute")
    assert_link("Download CSV", :href => /interval=minute/)
  end

  def test_date_range_picker
    assert_date_range_picker("/stats/logs")
  end

  def test_filter_options
    admin_login
    visit "/admin/#/stats/logs"
    refute_selector(".busy-blocker")

    assert_select "query_builder_rule_0_filter", :selected => "Response: API Umbrella Denied Code", :options => [
      "------",
      "Request: URL Host",
      "Request: URL Path",
      "Request: URL Scheme",
      "Request: URL Query String",
      ($config["opensearch"]["template_version"] < 2 ? "Request: Full URL & Query String" : nil),
      "Request: HTTP Method",
      "Request: IP Address",
      "Request: IP Country",
      "Request: IP State/Region",
      "Request: IP City",
      "Request: User Agent",
      "Request: User Agent Family",
      "Request: User Agent Type",
      "Request: Referer",
      "Request: Origin",
      "Request: Accept",
      "Request: Accept Encoding",
      "Request: Content Type",
      "Request: Connection",
      "Request: Size",
      "Request: ID",
      "User: API Key",
      "User: E-mail",
      "User: ID",
      "Response: HTTP Status Code",
      "Response: API Umbrella Denied Code",
      "Response: Age",
      "Response: Cache",
      "Response: Cache Flags",
      "Response: Content Encoding",
      "Response: Content Length",
      "Response: Content Type",
      "Response: Server",
      "Response: Transfer Encoding",
      "Response: Load Time",
      "Response: Size",
      "Response: Custom Dimension 1",
      "Response: Custom Dimension 2",
      "Response: Custom Dimension 3",
      "API Backend: ID",
      "API Backend: Resolved Host",
      "API Backend: Response Code Details",
      "API Backend: Response Flags",
    ].compact
    assert_select "query_builder_rule_0_operator", :selected => "is null", :options => [
      "equal",
      "not equal",
      "is null",
      "is not null",
    ]
  end

  def test_table_displays_time_in_local_timezone
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_method => "OPTIONS")
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T08:23:31.273Z").utc, :request_method => "OPTIONS")
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T19:02:43.902Z").utc, :request_method => "OPTIONS")
    LogItem.refresh_indices!

    admin_login
    visit "/admin/#/stats/logs?search=&start_at=2015-01-12&end_at=2015-01-18&interval=day"
    refute_selector(".busy-blocker")

    assert_equal("2015-01-16 12:02:43 PM MST", find("#results_table table tbody tr:nth-child(1) td:first-child").text)
    assert_equal("2015-01-16 1:23:31 AM MST", find("#results_table table tbody tr:nth-child(2) td:first-child").text)
    assert_equal("2015-01-15 11:06:28 PM MST", find("#results_table table tbody tr:nth-child(3) td:first-child").text)
  end

  def test_table_displays_time_in_local_timezone_during_dst
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-07-16T06:06:28.816Z").utc, :request_method => "OPTIONS")
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-07-16T08:23:31.273Z").utc, :request_method => "OPTIONS")
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-07-16T19:02:43.902Z").utc, :request_method => "OPTIONS")
    LogItem.refresh_indices!

    admin_login
    visit "/admin/#/stats/logs?search=&start_at=2015-07-12&end_at=2015-07-18&interval=day"
    refute_selector(".busy-blocker")

    assert_equal("2015-07-16 1:02:43 PM MDT", find("#results_table table tbody tr:nth-child(1) td:first-child").text)
    assert_equal("2015-07-16 2:23:31 AM MDT", find("#results_table table tbody tr:nth-child(2) td:first-child").text)
    assert_equal("2015-07-16 12:06:28 AM MDT", find("#results_table table tbody tr:nth-child(3) td:first-child").text)
  end
end

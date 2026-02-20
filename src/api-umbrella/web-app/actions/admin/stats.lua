local AnalyticsCity = require "api-umbrella.web-app.models.analytics_city"
local AnalyticsSearch = require "api-umbrella.web-app.models.analytics_search"
local ApiUser = require "api-umbrella.web-app.models.api_user"
local add_error = require("api-umbrella.web-app.utils.model_ext").add_error
local analytics_policy = require "api-umbrella.web-app.policies.analytics_policy"
local array_last = require "api-umbrella.utils.array_last"
local capture_errors_json = require("api-umbrella.web-app.utils.capture_errors").json
local cjson = require("cjson")
local config = require("api-umbrella.utils.load_config")()
local countries = require "api-umbrella.web-app.utils.countries"
local csrf_validate_token_or_admin_token_filter = require("api-umbrella.web-app.utils.csrf").validate_token_or_admin_token_filter
local csv = require "api-umbrella.web-app.utils.csv"
local datatables = require "api-umbrella.web-app.utils.datatables"
local db = require "lapis.db"
local formatted_interval_time = require "api-umbrella.web-app.utils.formatted_interval_time"
local is_empty = require "api-umbrella.utils.is_empty"
local json_null = require("cjson").null
local json_null_default = require "api-umbrella.web-app.utils.json_null_default"
local json_response = require "api-umbrella.web-app.utils.json_response"
local number_with_delimiter = require "api-umbrella.web-app.utils.number_with_delimiter"
local require_admin = require "api-umbrella.web-app.utils.require_admin"
local respond_to = require "api-umbrella.web-app.utils.respond_to"
local round = require "api-umbrella.utils.round"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local table_sub = require("pl.tablex").sub
local time = require "api-umbrella.utils.time"
local validation_ext = require "api-umbrella.web-app.utils.validation_ext"

local null = ngx.null
local gsub = ngx.re.gsub

local _M = {}

local function strip_api_key_from_query(query)
  local stripped
  if query then
    stripped = gsub(query, [[\bapi_key=?[^&]*(&|$)]], "", "ijo")
    stripped = gsub(stripped, [[&$]], "", "jo")
  end

  return stripped
end

local function sanitized_full_url(row)
  local url = row["request_scheme"] .. "://" .. row["request_host"] .. row["request_path"]
  if row["request_url_query"] then
    url = url .. "?" .. strip_api_key_from_query(row["request_url_query"])
  end

  return url
end

local function sanitized_url_path_and_query(row)
  local url = row["request_path"]
  if row["request_url_query"] then
    url = url .. "?" .. strip_api_key_from_query(row["request_url_query"])
  end

  return url
end

local function hits_over_time(interval, aggregations)
  local rows = {}
  if aggregations and aggregations["hits_over_time"] then
    for _, bucket in ipairs(aggregations["hits_over_time"]["buckets"]) do
      table.insert(rows, {
        c = {
          {
            v = bucket["key"],
            f = formatted_interval_time(interval, bucket["key"]),
          },
          {
            v = bucket["doc_count"],
            f = number_with_delimiter(bucket["doc_count"]),
          },
        }
      })
    end
  end

  return rows
end

local function aggregation_result(aggregations, name)
  local buckets = {}
  if aggregations then
    local top_buckets = aggregations["top_" .. name]["buckets"]
    local with_value_count = aggregations["value_count_" .. name]["value"]
    local missing_count = aggregations["missing_" .. name]["doc_count"]

    local other_hits = with_value_count
    for _, bucket in ipairs(top_buckets) do
      other_hits = other_hits - bucket["doc_count"]

      table.insert(buckets, {
        key = bucket["key"],
        count = bucket["doc_count"],
      })
    end

    if missing_count > 0 then
      local last_bucket = array_last(buckets)
      if #buckets < 10 or missing_count >= last_bucket["count"] then
        table.insert(buckets, {
          key = t("Missing / Unknown"),
          count = missing_count,
        })
      end
    end

    local total = with_value_count + missing_count
    for _, bucket in ipairs(buckets) do
      bucket["percent"] = round((bucket["count"] / total) * 100)
    end

    if other_hits > 0 then
      table.insert(buckets, {
        key = t("Other"),
        count = other_hits,
      })
    end
  end

  return buckets
end

local function get_country_name(country_code)
  assert(country_code)

  local name = country_code
  local country_name = countries.countries[country_code]
  if country_name then
    name = country_name
  end

  return t(name)
end

local function get_region_name(country_code, region_code)
  assert(country_code)
  assert(region_code)

  local name = region_code
  local regions = countries.subdivisions[country_code]
  if regions then
    local region_name = regions[region_code]
    if region_name then
      name = region_name
    end
  end

  return t(name)
end

local function get_child_region_id(filter_country, filter_region, code)
  if filter_country == "US" and not filter_region then
    return "US-" .. code
  else
    return code
  end
end

local function get_child_region_name(filter_country, filter_region, code)
  if not filter_country then
    return get_country_name(code)
  elseif filter_country == "US" and not filter_region then
    return get_region_name(filter_country, code)
  else
    return code
  end
end

local function fetch_city_locations(buckets, country, region)
  assert(buckets)
  assert(country)

  local city_names = {}
  for _, bucket in ipairs(buckets) do
    table.insert(city_names, string.lower(bucket["key"]))
  end

  local conditions = {}
  table.insert(conditions, "country = " .. db.escape_literal(country))
  if region then
    table.insert(conditions, "region = " .. db.escape_literal(region))
  end
  if not is_empty(city_names) then
    table.insert(conditions, "lower(city) IN " .. db.escape_literal(db.list(city_names)))
  end

  local cities = AnalyticsCity:select("WHERE " .. table.concat(conditions, " AND "), {
    fields = "city, location[0] AS lon, location[1] AS lat",
  })

  local data = {}
  local proper_city_names = {}
  for _, city in ipairs(cities) do
    if city.city then
      proper_city_names[string.lower(city.city)] = city.city
      data[city.city] = {
        lat = city.lat,
        lon = city.lon,
      }
    end
  end

  for _, bucket in ipairs(buckets) do
    local city_name = proper_city_names[bucket["key"]]
    if city_name then
      bucket["key"] = city_name
    end
  end

  return data
end

local function map_breadcrumbs(country, region)
  local breadcrumbs = {}
  if country then
    table.insert(breadcrumbs, {
      region = "world",
      name = t("World"),
    })

    local country_name = get_country_name(country)
    if region then
      table.insert(breadcrumbs, {
        region = country,
        name = country_name,
      })

      local region_name = get_region_name(country, region)
      table.insert(breadcrumbs, {
        name = region_name,
      })
    else
      table.insert(breadcrumbs, {
        name = country_name,
      })
    end
  end

  return breadcrumbs
end

local function region_location_columns(region_field, code, name, city_locations)
  assert(region_field)
  assert(code)

  local columns = {}
  if region_field == "request_ip_city" then
    assert(city_locations)

    local lat
    local lon
    local location = city_locations[code]
    if location then
      lat = location["lat"]
      lon = location["lon"]
    end

    table.insert(columns, { v = lat })
    table.insert(columns, { v = lon })
    table.insert(columns, { v = code })
  else
    table.insert(columns, {
      v = code,
      f = name,
    })
  end

  return columns
end

function _M.search(self)
  local search = AnalyticsSearch.factory(config["analytics"]["adapter"])
  search:set_start_time(self.params["start_at"])
  search:set_end_time(self.params["end_at"])
  search:set_interval(self.params["interval"])
  search:set_permission_scope(analytics_policy.authorized_query_scope(self.current_admin))
  search:set_search_query_string(self.params["search"])
  search:set_search_filters(self.params["query"])
  search:aggregate_by_interval()
  search:aggregate_by_users(10)
  search:aggregate_by_request_ip(10)
  search:aggregate_by_response_time_average()

  local results = search:fetch_results()

  -- Optimization: Every request should have an IP, so we don't need to perform
  -- extra aggregations to look for total counts and missing values, since we
  -- can assume the total count matches the overall hit count, and the missing
  -- IPs are zero. But we'll fake the structure needed for `aggregation_result`
  -- below.
  if results["aggregations"] then
    results["aggregations"]["value_count_request_ip"] = {
      value = results["hits"]["_total_value"],
    }
    results["aggregations"]["missing_request_ip"] = {
      doc_count = 0,
    }
  end

  local response = {
    stats = {
      total_hits = results["hits"]["_total_value"],
      total_users = 0,
      total_ips = 0,
      average_response_time = json_null,
    },
    hits_over_time = hits_over_time(search.interval, results["aggregations"]),
    aggregations = {
      users = aggregation_result(results["aggregations"], "user_email"),
      ips = aggregation_result(results["aggregations"], "request_ip"),
    },
  }

  if results["aggregations"] then
    response["stats"]["total_users"] = results["aggregations"]["unique_user_email"]["value"]
    response["stats"]["total_ips"] = results["aggregations"]["sampled_ips"]["unique_request_ip"]["value"]
    response["stats"]["average_response_time"] = results["aggregations"]["response_time_average"]["value"]
  end

  setmetatable(response["hits_over_time"], cjson.empty_array_mt)
  setmetatable(response["aggregations"]["users"], cjson.empty_array_mt)
  setmetatable(response["aggregations"]["ips"], cjson.empty_array_mt)
  return json_response(self, response)
end

function _M.logs(self)
  local limit = self.params["length"]
  if self.params["format"] == "csv" then
    limit = 500
  end

  local search = AnalyticsSearch.factory(config["analytics"]["adapter"])
  search:set_start_time(self.params["start_at"])
  search:set_end_time(self.params["end_at"])
  search:set_interval(self.params["interval"])
  search:set_permission_scope(analytics_policy.authorized_query_scope(self.current_admin))
  search:set_search_query_string(self.params["search"])
  search:set_search_filters(self.params["query"])
  search:set_offset(self.params["start"])
  search:set_limit(limit)
  search:set_sort(datatables.parse_order(self))

  if self.params["format"] == "csv" then
    csv.set_response_headers(self, "api_logs_" .. os.date("!%Y-%m-%d", ngx.now()) .. ".csv")
    ngx.say(csv.row_to_csv({
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
    }))
    ngx.flush(true)

    search:fetch_results_bulk(function(hits)
      for _, hit in ipairs(hits) do
        local row = hit["_source"]
        ngx.say(csv.row_to_csv({
          time.opensearch_to_csv(row["@timestamp"]) or null,
          row["request_method"] or null,
          row["request_host"] or null,
          sanitized_full_url(row) or null,
          row["user_email"] or null,
          row["request_ip"] or null,
          row["request_ip_country"] or null,
          row["request_ip_region"] or null,
          row["request_ip_city"] or null,
          row["response_status"] or null,
          row["gatekeeper_denied_code"] or null,
          row["response_time"] or null,
          row["response_content_type"] or null,
          row["request_accept_encoding"] or null,
          row["request_user_agent"] or null,
          row["request_user_agent_family"] or null,
          row["request_user_agent_type"] or null,
          row["request_referer"] or null,
          row["request_origin"] or null,
          row["request_accept"] or null,
          row["request_connection"] or null,
          row["request_content_type"] or null,
          row["request_size"] or null,
          row["response_age"] or null,
          row["response_cache"] or null,
          row["response_cache_flags"] or null,
          row["response_content_encoding"] or null,
          row["response_content_length"] or null,
          row["response_server"] or null,
          row["response_size"] or null,
          row["response_transfer_encoding"] or null,
          row["response_custom1"] or null,
          row["response_custom2"] or null,
          row["response_custom3"] or null,
          row["user_id"] or null,
          row["api_backend_id"] or null,
          row["api_backend_resolved_host"] or null,
          row["api_backend_response_code_details"] or null,
          row["api_backend_response_flags"] or null,
          hit["request_id"] or null,
        }))
      end
      ngx.flush(true)
    end)

    return { layout = false }
  else
    local results = search:fetch_results()
    local response = {
      draw = tonumber(self.params["draw"]) or 0,
      recordsTotal = results["hits"]["_total_value"],
      recordsFiltered = results["hits"]["_total_value"],
      data = {}
    }

    for _, hit in ipairs(results["hits"]["hits"]) do
      local row = hit["_source"]
      row["api_key"] = nil
      row["_type"] = nil
      row["_score"] = nil
      row["_index"] = nil
      row["request_at"] = row["@timestamp"]
      row["@timestamp"] = nil
      row["request_url"] = sanitized_url_path_and_query(row)
      row["request_url_query"] = strip_api_key_from_query(row["request_url_query"])
      if row["request_query"] then
        row["request_query"]["api_key"] = nil
      end

      table.insert(response["data"], row)
    end

    setmetatable(response["data"], cjson.empty_array_mt)
    return json_response(self, response)
  end
end

function _M.users(self)
  local limit = self.params["length"]
  if self.params["format"] == "csv" then
    limit = 100000
  end

  -- If we're sorting by hits or last request date, then we can perform the
  -- sorting directly in the opensearch query. Otherwise, for user-based
  -- field, we'll need to defer sorting until we have all the results in the
  -- app.
  local order_fields = datatables.parse_order(self)
  local order_column
  local order_dir
  local order
  if order_fields and order_fields[1] then
    local order_field = order_fields[1]
    order_column = order_field[1]
    order_dir = string.lower(order_field[2])

    if order_column == "hits" then
      order = { _count = order_dir }
    elseif order_column == "last_request_at" then
      order = { [order_column] = order_dir }
    end
  end

  local search = AnalyticsSearch.factory(config["analytics"]["adapter"])
  search:set_start_time(self.params["start_at"])
  search:set_end_time(self.params["end_at"])
  search:set_permission_scope(analytics_policy.authorized_query_scope(self.current_admin))
  search:set_search_query_string(self.params["search"])
  search:set_search_filters(self.params["query"])
  search:aggregate_by_user_stats(order)
  search:set_offset(self.params["start"])

  local results = search:fetch_results()
  local buckets
  if results["aggregations"] then
    buckets = results["aggregations"]["user_stats"]["buckets"]
  else
    buckets = {}
  end
  local total_count = #buckets

  -- If we were sorting by one of the facet fields, then the sorting has
  -- already been done by opensearch. We can improve the performance by
  -- going ahead and truncating the results to the specified page.
  if order then
    buckets = table_sub(buckets, 1, tonumber(limit))
  end

  local user_ids = {}
  for _, bucket in ipairs(buckets) do
    table.insert(user_ids, bucket["key"])
  end

  local users_by_id = {}
  if not is_empty(user_ids) then
    local users = ApiUser:select("WHERE id IN ?", db.list(user_ids))
    for _, user in ipairs(users) do
      users_by_id[user.id] = user
    end
  end

  -- Build up the results, combining the stats facet information with the user
  -- details.
  local user_data = {}
  for _, bucket in ipairs(buckets) do
    local user_id = bucket["key"]
    local user = users_by_id[user_id] or {}

    table.insert(user_data, {
      id = json_null_default(user_id),
      email = json_null_default(user.email),
      first_name = json_null_default(user.first_name),
      last_name = json_null_default(user.last_name),
      website = json_null_default(user.website),
      registration_source = json_null_default(user.registration_source),
      created_at = json_null_default(time.postgres_to_iso8601(user.created_at)),
      hits = json_null_default(bucket["doc_count"]),
      last_request_at = json_null_default(time.timestamp_ms_to_iso8601(bucket["last_request_at"]["value"])),
      use_description = json_null_default(user.use_description),
    })
  end

  -- If sorting was on any of the user fields, now that we have a full result
  -- set now we can manually sort and paginate.
  if not order and order_column and order_dir then
    table.sort(user_data, function(a, b)
      if order_dir == "desc" then
        return tostring(a[order_column]) > tostring(b[order_column])
      else
        return tostring(a[order_column]) < tostring(b[order_column])
      end
    end)
  end

  if self.params["format"] == "csv" then
    csv.set_response_headers(self, "api_users_" .. os.date("!%Y-%m-%d", ngx.now()) .. ".csv")
    ngx.say(csv.row_to_csv({
      "Email",
      "First Name",
      "Last Name",
      "Website",
      "Registration Source",
      "Signed Up (UTC)",
      "Hits",
      "Last Request (UTC)",
      "Use Description",
    }))
    ngx.flush(true)

    for _, row in ipairs(user_data) do
      ngx.say(csv.row_to_csv({
        row["email"] or null,
        row["first_name"] or null,
        row["last_name"] or null,
        row["website"] or null,
        row["registration_source"] or null,
        time.iso8601_to_csv(row["created_at"]) or null,
        row["hits"] or null,
        time.iso8601_to_csv(row["last_request_at"]) or null,
        row["use_description"] or null,
      }))
    end
    ngx.flush(true)

    return { layout = false }
  else
    local response = {
      draw = tonumber(self.params["draw"]) or 0,
      recordsTotal = total_count,
      recordsFiltered = total_count,
      data = user_data,
    }
    setmetatable(response["data"], cjson.empty_array_mt)
    return json_response(self, response)
  end
end

function _M.map(self)
  local search = AnalyticsSearch.factory(config["analytics"]["adapter"])
  search:set_start_time(self.params["start_at"])
  search:set_end_time(self.params["end_at"])
  search:set_permission_scope(analytics_policy.authorized_query_scope(self.current_admin))
  search:set_search_query_string(self.params["search"])
  search:set_search_filters(self.params["query"])

  local region_param = self.params["region"]
  local region_field
  local filter_country
  local filter_region
  if region_param == "world" then
    region_field = "request_ip_country"
  elseif region_param == "US" then
    filter_country = region_param
    region_field = "request_ip_region"
  else
    region_field = "request_ip_city"

    local matches, match_err = ngx.re.match(region_param, [[^(US)-([A-Z]{2})$]], "jo")
    if matches then
      filter_country = matches[1]
      filter_region = matches[2]
    else
      if match_err then
        ngx.log(ngx.ERR, "regex error: ", match_err)
      end

      filter_country = region_param
    end

    local ok = validation_ext.string:minlen(1)(filter_country)
    if not ok then
      add_error(search.errors, "region", "region", t("wrong format"))
    end
  end

  if filter_country then
    search:filter_by_ip_country(filter_country)
  end
  if filter_region then
    search:filter_by_ip_region(filter_region)
  end
  search:aggregate_by_ip_region_field(region_field)

  local results = search:fetch_results()
  local buckets
  local unknown_hits = 0
  if results["aggregations"] then
    buckets = results["aggregations"]["regions"]["buckets"]
    unknown_hits = results["aggregations"]["missing_regions"]["doc_count"]
  else
    buckets = {}
  end

  local city_locations
  if region_field == "request_ip_city" then
    city_locations = fetch_city_locations(buckets, filter_country, filter_region)
  end

  if self.params["format"] == "csv" then
    csv.set_response_headers(self, "api_map_" .. os.date("!%Y-%m-%d", ngx.now()) .. ".csv")
    ngx.say(csv.row_to_csv({
      "Location",
      "Hits",
    }))
    ngx.flush(true)

    for _, bucket in ipairs(buckets) do
      local code = bucket["key"]
      ngx.say(csv.row_to_csv({
        get_child_region_name(filter_country, filter_region, code) or null,
        bucket["doc_count"] or null,
      }))
    end

    if unknown_hits > 0 then
      ngx.say(csv.row_to_csv({
        t("Unknown") or null,
        unknown_hits or null,
      }))
    end
    ngx.flush(true)

    return { layout = false }
  else
    local response = {
      region_field = region_field,
      regions = {},
      map_regions = {},
      map_breadcrumbs = map_breadcrumbs(filter_country, filter_region),
    }

    for _, bucket in ipairs(buckets) do
      local code = bucket["key"]
      local child_region_name = get_child_region_name(filter_country, filter_region, code)
      table.insert(response["regions"], {
        id = get_child_region_id(filter_country, filter_region, code),
        name = child_region_name,
        hits = bucket["doc_count"],
      })

      local columns = region_location_columns(region_field, bucket["key"], child_region_name, city_locations)
      table.insert(columns, {
        v = bucket["doc_count"],
        f = number_with_delimiter(bucket["doc_count"]),
      })
      table.insert(response["map_regions"], {
        c = columns
      })
    end

    if unknown_hits > 0 then
      table.insert(response["regions"], {
        id = "missing",
        name = t("Unknown"),
        hits = unknown_hits,
      })
    end

    setmetatable(response["regions"], cjson.empty_array_mt)
    setmetatable(response["map_regions"], cjson.empty_array_mt)
    setmetatable(response["map_breadcrumbs"], cjson.empty_array_mt)
    return json_response(self, response)
  end
end

return function(app)
  app:match("/admin/stats/search(.:format)", respond_to({ GET = require_admin(capture_errors_json(_M.search)) }))
  app:match("/admin/stats/logs(.:format)", respond_to({
    GET = require_admin(capture_errors_json(_M.logs)),
    POST = csrf_validate_token_or_admin_token_filter(require_admin(capture_errors_json(_M.logs))),
  }))
  app:match("/admin/stats/users(.:format)", respond_to({ GET = require_admin(capture_errors_json(_M.users)) }))
  app:match("/admin/stats/map(.:format)", respond_to({ GET = require_admin(capture_errors_json(_M.map)) }))
end

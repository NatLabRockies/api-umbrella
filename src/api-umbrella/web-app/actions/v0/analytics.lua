local AnalyticsSearch = require "api-umbrella.web-app.models.analytics_search"
local Cache = require "api-umbrella.web-app.models.cache"
local analytics_policy = require "api-umbrella.web-app.policies.analytics_policy"
local capture_errors_json = require("api-umbrella.web-app.utils.capture_errors").json
local config = require("api-umbrella.utils.load_config")()
local icu_date = require "icu-date-ffi"
local int64_to_json_number = require("api-umbrella.utils.int64").to_json_number
local interval_lock = require "api-umbrella.utils.interval_lock"
local json_decode = require("cjson").decode
local json_encode = require "api-umbrella.utils.json_encode"
local json_response = require "api-umbrella.web-app.utils.json_response"
local pg_utils = require "api-umbrella.utils.pg_utils"
local respond_to = require "api-umbrella.web-app.utils.respond_to"
local stable_object_hash = require "api-umbrella.utils.stable_object_hash"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local time = require "api-umbrella.utils.time"
local timer_at = require "api-umbrella.web-app.utils.timer_at"

local db_statement_timeout_ms = config["web"]["analytics_v0_summary_db_timeout"] * 1000

local _M = {}

local function generate_organization_summary(organization_name, start_time, end_time, recent_start_time, filters)
  local cache_id = "analytics_summary:organization:" .. organization_name .. ":" .. start_time .. ":" .. end_time .. ":" .. recent_start_time .. ":" .. stable_object_hash({
    filters = filters,
    timezone = config["analytics"]["timezone"],
    max_buckets = config["opensearch"]["max_buckets"],
    analytics_v0_summary_filter = config["web"]["analytics_v0_summary_filter"],
  })
  local cache = Cache:find(cache_id)
  if cache then
    ngx.log(ngx.NOTICE, "Using cached analytics response for " .. cache_id)
    return json_decode(cache.data)
  end
  ngx.log(ngx.NOTICE, "Fetching new analytics response for " .. cache_id)

  local search = AnalyticsSearch.factory(config["analytics"]["adapter"])
  search:set_start_time(start_time)
  search:set_end_time(end_time)
  search:set_interval("month")
  search:unset_sort()
  search:filter_exclude_imported()
  search:aggregate_by_interval()
  search:aggregate_by_unique_user_ids()
  search:aggregate_by_response_time_average()
  if config["web"]["analytics_v0_summary_filter"] then
    search:set_search_query_string(config["web"]["analytics_v0_summary_filter"])
  end
  search:set_timeout(config["web"]["analytics_v0_summary_analytics_timeout"])
  search:set_permission_scope(filters)

  local aggregate_sql = [[
    WITH interval_rows AS (
      SELECT
        substring(data_date from 1 for :date_key_length) AS interval_date,
        hit_count,
        unique_user_ids,
        response_time_average
      FROM analytics_cache
      WHERE id IN :ids
    ),
    interval_unique_user_ids AS (
      SELECT
        interval_date,
        array_agg(DISTINCT user_ids.user_id) FILTER (WHERE user_ids.user_id IS NOT NULL) AS unique_user_ids
      FROM interval_rows
      CROSS JOIN LATERAL unnest(unique_user_ids) AS user_ids(user_id)
      GROUP BY interval_date
    ),
    interval_counts AS (
      SELECT
        interval_date,
        SUM(hit_count) AS hit_count,
        SUM(response_time_average) AS response_time_average
      FROM interval_rows
      GROUP BY interval_date
    ),
    interval_totals AS (
      SELECT
        interval_counts.interval_date,
        interval_counts.hit_count,
        interval_unique_user_ids.unique_user_ids,
        interval_counts.response_time_average
      FROM interval_counts
      NATURAL LEFT JOIN interval_unique_user_ids
      ORDER BY interval_date
    ),
    all_unique_users AS (
      SELECT COUNT(DISTINCT user_ids.user_id) FILTER (WHERE user_ids.user_id IS NOT NULL) AS total_unique_users
      FROM interval_totals
      LEFT JOIN LATERAL unnest(interval_totals.unique_user_ids) AS user_ids(user_id) ON true
    )
    SELECT jsonb_build_object(
      'hits', jsonb_build_object(
        :interval_name, jsonb_agg(jsonb_build_array(interval_totals.interval_date, COALESCE(interval_totals.hit_count, 0))),
        'total', SUM(interval_totals.hit_count)
      ),
      'active_api_keys', jsonb_build_object(
        :interval_name, jsonb_agg(jsonb_build_array(interval_totals.interval_date, COALESCE(array_length(interval_totals.unique_user_ids, 1), 0))),
        'total', (SELECT total_unique_users FROM all_unique_users)
      ),
      'average_response_times', jsonb_build_object(
        :interval_name, jsonb_agg(jsonb_build_array(interval_totals.interval_date, interval_totals.response_time_average)),
        'average', ROUND(SUM(CASE WHEN interval_totals.response_time_average IS NOT NULL AND interval_totals.hit_count IS NOT NULL THEN interval_totals.response_time_average * interval_totals.hit_count END) / SUM(CASE WHEN interval_totals.response_time_average IS NOT NULL AND interval_totals.hit_count IS NOT NULL THEN interval_totals.hit_count END))
      )
    ) AS response
    FROM interval_totals
  ]]

  -- Expire the monthly data in 3 months. While the historical data shouldn't
  -- really change, the API scopes may change (which are part of
  -- the cache key), so for that reason, don't keep old data around
  -- indefinitely. But since we update the expires_at timestamp on rows that
  -- are still being accessed, this should ensure we only expire unused data.
  local expires_at = ngx.now() + 60 * 60 * 24 * 30 * 3
  local analytics_cache_ids = search:cache_interval_results(expires_at)
  local response = pg_utils.query(aggregate_sql, {
    ids = pg_utils.list(analytics_cache_ids),
    interval_name = "monthly",
    date_key_length = 7,
  }, {
    fatal = true,
    statement_timeout = db_statement_timeout_ms,
  })[1]["response"]

  search:set_start_time(recent_start_time)
  search:set_end_time(end_time)
  search:set_interval("day")
  search:aggregate_by_interval()
  expires_at = ngx.now() + 60 * 60 * 24 * 30 -- 30 days
  local recent_analytics_cache_ids = search:cache_interval_results(expires_at)
  local recent_response = pg_utils.query(aggregate_sql, {
    ids = pg_utils.list(recent_analytics_cache_ids),
    interval_name = "daily",
    date_key_length = 10,
  }, {
    fatal = true,
    statement_timeout = db_statement_timeout_ms,
  })[1]["response"]

  response["hits"]["recent"] = recent_response["hits"]
  response["active_api_keys"]["recent"] = recent_response["active_api_keys"]
  response["average_response_times"]["recent"] = recent_response["average_response_times"]

  -- Only cache the data if it includes the expected latest month of data, and
  -- also includes all months/days expected. This prevents returning and
  -- caching incomplete data due to the underlying analytics queries failing
  -- for certain time periods and forces the data to wait until all of the
  -- underlying data is cached before returning the overall summary data.
  local last_month = response["hits"]["monthly"][#response["hits"]["monthly"]]
  local expected_last_month = string.sub(end_time, 1, 7)
  local last_day = response["hits"]["recent"]["daily"][#response["hits"]["recent"]["daily"]]
  local expected_last_day = string.sub(end_time, 1, 10)
  if last_month[1] ~= expected_last_month or last_day[1] ~= expected_last_day or #analytics_cache_ids ~= #response["hits"]["monthly"] or #recent_analytics_cache_ids ~= #response["hits"]["recent"]["daily"] then
    return nil, "incomplete data"
  end

  local response_json = json_encode(response)
  expires_at = ngx.now() + 60 * 60 * 24 * 2 -- 2 days
  Cache:upsert(cache_id, response_json, expires_at)

  return response
end

local function generate_production_apis_summary(start_time, end_time, recent_start_time)
  local any_err = false

  local data = {
    organizations = {},
  }
  local counts = pg_utils.query([[
    SELECT COUNT(DISTINCT api_backends.organization_name) AS organization_count,
      COUNT(DISTINCT api_backends.id) AS api_backend_count,
      COUNT(DISTINCT api_backend_url_matches.id) AS api_backend_url_match_count
    FROM api_backends
      LEFT JOIN api_backend_url_matches ON api_backends.id = api_backend_url_matches.api_backend_id
    WHERE api_backends.status_description = 'Production'
  ]], nil, {
    fatal = true,
    statement_timeout = db_statement_timeout_ms,
  })
  data["organization_count"] = int64_to_json_number(counts[1]["organization_count"])
  data["api_backend_count"] = int64_to_json_number(counts[1]["api_backend_count"])
  data["api_backend_url_match_count"] = int64_to_json_number(counts[1]["api_backend_url_match_count"])

  local all_filters = {
    condition = "OR",
    rules = {},
  }

  local organizations = pg_utils.query([[
    SELECT api_backends.organization_name,
      COUNT(DISTINCT api_backends.id) AS api_backend_count,
      COUNT(DISTINCT api_backend_url_matches.id) AS api_backend_url_match_count,
      json_agg(json_build_object('frontend_host', api_backends.frontend_host, 'frontend_prefix', api_backend_url_matches.frontend_prefix)) AS url_prefixes
    FROM api_backends
      LEFT JOIN api_backend_url_matches ON api_backends.id = api_backend_url_matches.api_backend_id
    WHERE api_backends.status_description = 'Production'
    GROUP BY api_backends.organization_name
    ORDER BY api_backends.organization_name
  ]], nil, {
    fatal = true,
    statement_timeout = db_statement_timeout_ms,
  })
  for _, organization in ipairs(organizations) do
    local filters = {
      condition = "OR",
      rules = {},
    }
    for _, url_prefix in ipairs(organization["url_prefixes"]) do
      local rule = {
        condition = "AND",
        rules = {
          {
            field = "request_host",
            operator = "equal",
            value = string.lower(url_prefix["frontend_host"]),
          },
          {
            field = "request_path",
            operator = "begins_with",
            value = string.lower(url_prefix["frontend_prefix"]),
          },
        },
      }
      table.insert(filters["rules"], rule)
      table.insert(all_filters["rules"], rule)
    end

    ngx.log(ngx.NOTICE, 'Fetching analytics for organization "' .. organization["organization_name"] .. '"')
    local organization_data, organization_data_err = generate_organization_summary(organization["organization_name"], start_time, end_time, recent_start_time, filters)
    if organization_data_err then
      ngx.log(ngx.ERR, 'Analytics for organization "' .. organization["organization_name"] .. '" failed: ', organization_data_err)
      any_err = true
    else
      organization_data["name"] = organization["organization_name"]
      organization_data["api_backend_count"] = int64_to_json_number(organization["api_backend_count"])
      organization_data["api_backend_url_match_count"] = int64_to_json_number(organization["api_backend_url_match_count"])
      table.insert(data["organizations"], organization_data)
    end
  end

  ngx.log(ngx.NOTICE, "Fetching analytics for all organizations")
  local all_data, all_data_err = generate_organization_summary("all", start_time, end_time, recent_start_time, all_filters)
  if all_data_err then
    ngx.log(ngx.ERR, "Analytics for all organization failed: ", all_data_err)
    any_err = true
  else
    data["all"] = all_data
  end

  if any_err then
    return nil, "incomplete data"
  else
    return data
  end
end

local function generate_summary()
  local date_tz = icu_date.new({
    zone_id = config["analytics"]["timezone"],
  })
  local format_iso8601 = icu_date.formats.iso8601()

  date_tz:parse(format_iso8601, config["web"]["analytics_v0_summary_start_time"])
  date_tz:set_time_zone_id(config["analytics"]["timezone"])
  local start_time = date_tz:format(format_iso8601)
  local start_time_ms = date_tz:get_millis()

  if config["web"]["analytics_v0_summary_end_time"] then
    date_tz:parse(format_iso8601, config["web"]["analytics_v0_summary_end_time"])
    date_tz:set_time_zone_id(config["analytics"]["timezone"])
  else
    date_tz:set_millis(ngx.now() * 1000)
    date_tz:add(icu_date.fields.DATE, -1)
    date_tz:set(icu_date.fields.HOUR_OF_DAY, 23)
    date_tz:set(icu_date.fields.MINUTE, 59)
    date_tz:set(icu_date.fields.SECOND, 59)
    date_tz:set(icu_date.fields.MILLISECOND, 999)
  end
  local end_time = date_tz:format(format_iso8601)
  local end_time_ms = date_tz:get_millis()

  date_tz:add(icu_date.fields.DATE, -29)
  date_tz:set(icu_date.fields.HOUR_OF_DAY, 0)
  date_tz:set(icu_date.fields.MINUTE, 0)
  date_tz:set(icu_date.fields.SECOND, 0)
  date_tz:set(icu_date.fields.MILLISECOND, 0)
  local recent_start_time = date_tz:format(format_iso8601)

  local production_apis, production_apis_err = generate_production_apis_summary(start_time, end_time, recent_start_time)
  if production_apis_err then
    ngx.log(ngx.ERR, "Production APIs summary error: ", production_apis_err)
  else
    local response = {
      production_apis = production_apis,
      start_time = time.timestamp_ms_to_iso8601(start_time_ms),
      end_time = time.timestamp_ms_to_iso8601(end_time_ms),
      timezone = date_tz:get_time_zone_id(),
    }

    response["cached_at"] = time.timestamp_to_iso8601(ngx.now())

    local cache_id = "analytics_summary"
    local response_json = json_encode(response)
    local expires_at = nil -- Never expire
    Cache:upsert(cache_id, response_json, expires_at)
  end
end

function _M.summary(self)
  analytics_policy.authorize_summary()

  self.res.headers["Access-Control-Allow-Origin"] = "*"
  local response_json

  -- Try to fetch the summary data out of the cache.
  local cache = Cache:find("analytics_summary")
  if cache then
    self.res.headers["X-Cache"] = "HIT"
    response_json = cache.data

    -- If the cached data is older than 6 hours, then go ahead and an re-fetch
    -- and cache the data asynchronously in the background. Since this takes a
    -- while to generate, we want ensure we always have valid cached data (so
    -- users don't get a super slow response and we don't overwhelm the server
    -- when it's uncached).
    if cache:updated_at_timestamp() < ngx.now() - 60 * 60 * 6 then
      timer_at(0, function()
        -- Ensure only one pre-seed is happening at a time (at least per
        -- server).
        interval_lock.mutex_exec("preseed_analytics_summary_cache", generate_summary)
      end)
    end
  else
    -- If it's not cached, generate it now.
    self.res.headers["X-Cache"] = "MISS"

    -- Trigger analytics generation in background so if it takes longer than
    -- this request, it can still populate.
    timer_at(0, function()
      -- Ensure only one pre-seed is happening at a time (at least per
      -- server).
      interval_lock.mutex_exec("initial_analytics_summary_cache", generate_summary)
    end)

    -- Poll for cache to be populated up to 60 seconds.
    local timeout_at = ngx.now() + 30
    while true do
      cache = Cache:find("analytics_summary")
      if cache then
        response_json = cache.data
        break
      end

      if ngx.now() > timeout_at then
        ngx.ctx.error_status = 503
        return coroutine.yield("error", {
          _render = {
            errors = {
              {
                code = "TEMPORARILY_UNAVAILABLE",
                message = t("Content is temporarily unavailable"),
              },
            },
          },
        })
      end

      ngx.sleep(0.5)
    end
  end

  return json_response(self, response_json)
end

return function(app)
  app:match("/api-umbrella/v0/analytics/summary(.:format)", respond_to({ GET = capture_errors_json(_M.summary) }))
end

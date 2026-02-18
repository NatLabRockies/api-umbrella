local AnalyticsSearch = require "api-umbrella.web-app.models.analytics_search"
local analytics_policy = require "api-umbrella.web-app.policies.analytics_policy"
local capture_errors_json = require("api-umbrella.web-app.utils.capture_errors").json
local cjson = require("cjson")
local config = require("api-umbrella.utils.load_config")()
local csv = require "api-umbrella.web-app.utils.csv"
local endswith = require("pl.stringx").endswith
local formatted_interval_time = require "api-umbrella.web-app.utils.formatted_interval_time"
local json_response = require "api-umbrella.web-app.utils.json_response"
local number_with_delimiter = require "api-umbrella.web-app.utils.number_with_delimiter"
local path_join = require "api-umbrella.utils.path_join"
local require_admin = require "api-umbrella.web-app.utils.require_admin"
local respond_to = require "api-umbrella.web-app.utils.respond_to"
local split = require("ngx.re").split
local table_sub = require("pl.tablex").sub

local null = ngx.null

local _M = {}

local function drilldown_breadcrumbs(self)
  local breadcrumbs = {
    {
      crumb = "All Hosts",
      prefix = "0/",
    },
  }

  local path = split(self.params["prefix"], "/", "jo", nil, 2)[2]
  local parents = split(path, "/", "jo")
  for index, parent in ipairs(parents) do
    if parent and parent ~= "" then
      local level_path_parts = table_sub(parents, 1, index)
      table.insert(breadcrumbs, {
        crumb = parent,
        prefix = path_join(index, table.concat(level_path_parts, "/"), "/"),
      })
    end
  end

  return breadcrumbs
end

local function drilldown_results(raw_results, search)
  local results = {}

  local depth = search.drilldown_depth
  local descendent_depth = depth + 1

  if raw_results and raw_results["aggregations"] and raw_results["aggregations"]["drilldown"] then
    local buckets = raw_results["aggregations"]["drilldown"]["buckets"]
    for _, bucket in ipairs(buckets) do
      local path
      if config["opensearch"]["template_version"] < 2 then
        local parts = split(bucket["key"], "/", "jo", nil, 2)
        path = parts[2]
      else
        path = path_join(search.drilldown_parent, bucket["key"])
      end

      local descendent_prefix = path_join(descendent_depth, path)
      local terminal = true
      if endswith(path, "/") then
        terminal = false
      end

      table.insert(results, {
        depth = depth,
        path = path,
        terminal = terminal,
        descendent_prefix = descendent_prefix,
        hits = bucket["doc_count"],
      })
    end
  end

  return results
end

local function drilldown_hits_over_time(raw_results, search)
  local hits_over_time = {
    cols = {
      { id = "date", label = "Date", type = "datetime" },
    },
    rows = {},
  }

  if raw_results["aggregations"] then
    local path_buckets = raw_results["aggregations"]["top_path_hits_over_time"]["buckets"]
    for _, bucket in ipairs(path_buckets) do
      local id
      local label
      if config["opensearch"]["template_version"] < 2 then
        id = bucket["key"]
        label = split(bucket["key"], "/", "jo", nil, 2)[2]
      else
        id = path_join(search.drilldown_depth, search.drilldown_parent, bucket["key"])
        label = path_join(search.drilldown_parent, bucket["key"])
      end

      table.insert(hits_over_time["cols"], {
        id = id,
        label = label,
        type = "number",
      })
    end

    local has_other_hits = false
    local total_buckets = raw_results["aggregations"]["hits_over_time"]["buckets"]
    for index, total_bucket in ipairs(total_buckets) do
      local cells = {
        {
          v = total_bucket["key"],
          f = formatted_interval_time(search.interval, total_bucket["key"]),
        },
      }

      local path_total_hits = 0
      for _, path_bucket in ipairs(path_buckets) do
        local bucket = path_bucket["drilldown_over_time"]["buckets"][index]
        table.insert(cells, {
          v = bucket["doc_count"],
          f = number_with_delimiter(bucket["doc_count"]),
        })

        path_total_hits = path_total_hits + bucket["doc_count"]
      end

      local other_hits = total_bucket["doc_count"] - path_total_hits
      if other_hits > 0 then
        has_other_hits = true
      end
      table.insert(cells, {
        v = other_hits,
        f = number_with_delimiter(other_hits),
      })

      table.insert(hits_over_time["rows"], {
        c = cells,
      })
    end

    if has_other_hits then
      table.insert(hits_over_time["cols"], {
        id = "other",
        label = "Other",
        type = "number",
      })
    else
      for _, row in ipairs(hits_over_time["rows"]) do
        table.remove(row["c"])
      end
    end
  end

  return hits_over_time
end

function _M.drilldown(self)
  local search = AnalyticsSearch.factory(config["analytics"]["adapter"])
  search:set_start_time(self.params["start_at"])
  search:set_end_time(self.params["end_at"])
  search:set_interval(self.params["interval"])
  search:set_permission_scope(analytics_policy.authorized_query_scope(self.current_admin))
  search:set_search_query_string(self.params["search"])
  search:set_search_filters(self.params["query"])

  local drilldown_size = 500
  if self.params["format"] == "csv" then
    drilldown_size = nil
  end
  search:aggregate_by_drilldown(self.params["prefix"], drilldown_size)

  if self.params["format"] ~= "csv" then
    search:aggregate_by_drilldown_over_time(self.params["hits_over_time_max_buckets"])
  end

  local raw_results = search:fetch_results()
  local results = drilldown_results(raw_results, search)

  if self.params["format"] == "csv" then
    csv.set_response_headers(self, "api_drilldown_" .. os.date("!%Y-%m-%d", ngx.now()) .. ".csv")
    ngx.say(csv.row_to_csv({
      "Path",
      "Hits",
    }))
    ngx.flush(true)

    for _, result in ipairs(results) do
      ngx.say(csv.row_to_csv({
        result["path"] or null,
        result["hits"] or null,
      }))
    end
    ngx.flush(true)

    return { layout = false }
  else
    local response = {
      results = results,
      hits_over_time = drilldown_hits_over_time(raw_results, search),
      breadcrumbs = drilldown_breadcrumbs(self),
    }
    setmetatable(response["results"], cjson.empty_array_mt)
    setmetatable(response["hits_over_time"]["cols"], cjson.empty_array_mt)
    setmetatable(response["hits_over_time"]["rows"], cjson.empty_array_mt)
    setmetatable(response["breadcrumbs"], cjson.empty_array_mt)
    return json_response(self, response)
  end
end

return function(app)
  app:match("/api-umbrella/v1/analytics/drilldown(.:format)", respond_to({ GET = require_admin(capture_errors_json(_M.drilldown)) }))
end

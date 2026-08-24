local AgentLoopEvent = require "api-umbrella.web-app.models.agent_loop_event"
local AgentLoopTarget = require "api-umbrella.web-app.models.agent_loop_target"
local capture_errors_json_full = require("api-umbrella.web-app.utils.capture_errors").json_full
local csrf_validate_token_or_admin_token_filter = require("api-umbrella.web-app.utils.csrf").validate_token_or_admin_token_filter
local json_response = require "api-umbrella.web-app.utils.json_response"
local db = require "lapis.db"
local require_admin = require "api-umbrella.web-app.utils.require_admin"
local respond_to = require "api-umbrella.web-app.utils.respond_to"
local validation_ext = require "api-umbrella.web-app.utils.validation_ext"
local wrapped_json_params = require "api-umbrella.web-app.utils.wrapped_json_params"

local _M = {}

local function json_array(records)
  local data = {}
  for _, record in ipairs(records) do
    table.insert(data, record:as_json())
  end

  return data
end

local function filtered_targets(self)
  local conditions = {}
  if self.params["agent_id"] then
    if validation_ext.string.uuid(self.params["agent_id"]) then
      table.insert(conditions, "agent_id = " .. db.escape_literal(self.params["agent_id"]))
    else
      table.insert(conditions, "1 = 0")
    end
  end
  if self.params["state"] then
    table.insert(conditions, "state = " .. db.escape_literal(self.params["state"]))
  end

  local where = ""
  if #conditions > 0 then
    where = "WHERE " .. table.concat(conditions, " AND ") .. " "
  end

  return AgentLoopTarget:select(where .. "ORDER BY updated_at DESC")
end

function _M.standings(self)
  return json_response(self, {
    standings = AgentLoopTarget.standings(),
  })
end

function _M.index_targets(self)
  return json_response(self, {
    targets = json_array(filtered_targets(self)),
  })
end

function _M.show_target(self)
  return json_response(self, {
    target = self.target:as_json(),
  })
end

function _M.create_target(self)
  local target = assert(AgentLoopTarget:authorized_create(_M.target_params(self)))
  assert(AgentLoopEvent:authorized_create({
    target_id = target.id,
    event_type = "assigned",
    summary = "Target assigned",
    source = "manual",
  }))

  self.res.status = 201
  return json_response(self, {
    target = target:as_json(),
    events = json_array(AgentLoopEvent.for_target(target.id)),
  })
end

function _M.index_events(self)
  return json_response(self, {
    events = json_array(AgentLoopEvent.for_target(self.target.id)),
  })
end

function _M.create_event(self)
  local event = assert(AgentLoopEvent:authorized_create(_M.event_params(self)))
  self.res.status = 201
  return json_response(self, {
    event = event:as_json(),
    target = assert(AgentLoopTarget:find(self.target.id)):as_json(),
  })
end

function _M.target_params(self)
  local params = {}
  if self.params and type(self.params["target"]) == "table" then
    local input = self.params["target"]
    params = {
      agent_id = input["agent_id"],
      name = input["name"],
      description = input["description"],
      mentor_admin_id = input["mentor_admin_id"],
      responsibility_tier = input["responsibility_tier"],
      metadata = input["metadata"],
    }
  end

  return params
end

function _M.event_params(self)
  local params = {}
  if self.params and type(self.params["event"]) == "table" then
    local input = self.params["event"]
    params = {
      target_id = self.target.id,
      event_type = input["event_type"],
      summary = input["summary"],
      evidence = input["evidence"],
      outcome = input["outcome"],
      score = input["score"],
      grade_label = input["grade_label"],
      responsibility_tier = input["responsibility_tier"],
      reputation_delta = input["reputation_delta"],
      asset_value_delta = input["asset_value_delta"],
      source = input["source"],
      deduplication_key = input["deduplication_key"],
      metadata = input["metadata"],
    }
  end

  return params
end

return function(app)
  app:match("/api-umbrella/v1/agent-loop/standings(.:format)", respond_to({
    before = require_admin(),
    GET = capture_errors_json_full(_M.standings),
  }))

  app:match("/api-umbrella/v1/agent-loop/targets/:id/events(.:format)", respond_to({
    before = require_admin(function(self)
      if validation_ext.string.uuid(self.params["id"]) then
        self.target = AgentLoopTarget:find(self.params["id"])
      end
      if not self.target then
        return self.app.handle_404(self)
      end
    end),
    GET = capture_errors_json_full(_M.index_events),
    POST = csrf_validate_token_or_admin_token_filter(capture_errors_json_full(wrapped_json_params(_M.create_event, "event"))),
  }))

  app:match("/api-umbrella/v1/agent-loop/targets/:id(.:format)", respond_to({
    before = require_admin(function(self)
      if validation_ext.string.uuid(self.params["id"]) then
        self.target = AgentLoopTarget:find(self.params["id"])
      end
      if not self.target then
        return self.app.handle_404(self)
      end
    end),
    GET = capture_errors_json_full(_M.show_target),
  }))

  app:match("/api-umbrella/v1/agent-loop/targets(.:format)", respond_to({
    before = require_admin(),
    GET = capture_errors_json_full(_M.index_targets),
    POST = csrf_validate_token_or_admin_token_filter(capture_errors_json_full(wrapped_json_params(_M.create_target, "target"))),
  }))
end

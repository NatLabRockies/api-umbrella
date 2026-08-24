local AgentLoopTarget = require "api-umbrella.web-app.models.agent_loop_target"
local cjson = require("cjson")
local db = require "lapis.db"
local is_hash = require "api-umbrella.utils.is_hash"
local json_null_default = require "api-umbrella.web-app.utils.json_null_default"
local model_ext = require "api-umbrella.web-app.utils.model_ext"
local pg_encode_json = require("pgmoon.json").encode_json
local t = require("api-umbrella.web-app.utils.gettext").gettext
local time = require "api-umbrella.utils.time"
local validation_ext = require "api-umbrella.web-app.utils.validation_ext"

local db_null = db.NULL
local db_raw = db.raw
local validate_field = model_ext.validate_field

local allowed_event_types = {
  assigned = true,
  work = true,
  evidence = true,
  grade = true,
  responsibility_change = true,
  re_evaluate = true,
  mentor_note = true,
}

local allowed_sources = {
  manual = true,
  automated = true,
}

local allowed_transitions = {
  assigned = { assigned = true, work = true, mentor_note = true },
  performed = { evidence = true, mentor_note = true },
  evidenced = { grade = true, mentor_note = true },
  graded = { responsibility_change = true, re_evaluate = true, work = true, mentor_note = true },
  responsibility_changed = { re_evaluate = true, work = true, mentor_note = true },
  re_evaluated = { work = true, evidence = true, responsibility_change = true, grade = true, mentor_note = true },
}

local target_state_by_event_type = {
  assigned = "assigned",
  work = "performed",
  evidence = "evidenced",
  grade = "graded",
  responsibility_change = "responsibility_changed",
  re_evaluate = "re_evaluated",
}

local function validate_number_range(errors, field, field_label, value, min, max)
  if value == nil or value == "" or value == db_null then
    return
  end

  local number = tonumber(value)
  if not number then
    model_ext.add_error(errors, field, field_label, t("is invalid"))
    return
  end

  if number < min or number > max then
    model_ext.add_error(errors, field, field_label, string.format(t("must be between %d and %d"), min, max))
  end
end

local function build_target_updates(self, target)
  local updates = {
    last_event_at = self.created_at,
  }

  local new_state = target_state_by_event_type[self.event_type]
  if new_state then
    updates["state"] = new_state
  end

  if (self.event_type == "grade" or self.event_type == "re_evaluate") and self.score ~= nil and self.score ~= db_null then
    updates["current_grade"] = self.score
    updates["current_grade_label"] = self.grade_label or target.current_grade_label
    updates["reputation_score"] = (tonumber(target.reputation_score) or 0) + (tonumber(self.reputation_delta) or 0)
    updates["asset_value"] = (tonumber(target.asset_value) or 0) + (tonumber(self.asset_value_delta) or 0)
  elseif self.event_type == "responsibility_change" and self.responsibility_tier then
    updates["responsibility_tier"] = self.responsibility_tier
  end

  if self.event_type == "re_evaluate" then
    updates["iteration_count"] = (tonumber(target.iteration_count) or 0) + 1
  end

  return updates
end

local AgentLoopEvent = model_ext.new_class("agent_loop_events", {
  as_json = function(self)
    return {
      id = json_null_default(self.id),
      target_id = json_null_default(self.target_id),
      event_type = json_null_default(self.event_type),
      summary = json_null_default(self.summary),
      evidence = json_null_default(self.evidence),
      outcome = json_null_default(self.outcome),
      score = json_null_default(self.score),
      grade_label = json_null_default(self.grade_label),
      responsibility_tier = json_null_default(self.responsibility_tier),
      reputation_delta = json_null_default(self.reputation_delta),
      asset_value_delta = json_null_default(self.asset_value_delta),
      source = json_null_default(self.source),
      deduplication_key = json_null_default(self.deduplication_key),
      metadata = json_null_default(self.metadata),
      created_at = json_null_default(time.postgres_to_iso8601(self.created_at)),
      created_by = json_null_default(self.created_by_id),
      updated_at = json_null_default(time.postgres_to_iso8601(self.updated_at)),
      updated_by = json_null_default(self.updated_by_id),
      deleted_at = cjson.null,
      version = 1,
    }
  end,
}, {
  authorize = function()
    return true
  end,

  before_validate_on_create = function(_, values)
    if values["source"] == nil or values["source"] == "" or values["source"] == db_null then
      values["source"] = "manual"
    end
  end,

  before_validate = function(_, values)
    for _, field in ipairs({ "score", "reputation_delta", "asset_value_delta" }) do
      if values[field] ~= nil and values[field] ~= db_null and values[field] ~= "" then
        values[field] = tonumber(values[field]) or values[field]
      end
    end
  end,

  validate = function(self, data)
    local errors = {}

    validate_field(errors, data, "target_id", t("Target"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.string.uuid, t("is invalid") },
    })

    local target
    if data["target_id"] and data["target_id"] ~= db_null and validation_ext.string.uuid(data["target_id"]) then
      target = AgentLoopTarget:find(data["target_id"])
      if not target then
        model_ext.add_error(errors, "target_id", t("Target"), t("is invalid"))
      end
    end

    validate_field(errors, data, "event_type", t("Event type"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.string:maxlen(50), string.format(t("is too long (maximum is %d characters)"), 50) },
    })
    if data["event_type"] and not allowed_event_types[data["event_type"]] then
      model_ext.add_error(errors, "event_type", t("Event type"), t("is invalid"))
    end

    validate_field(errors, data, "source", t("Source"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.string:maxlen(50), string.format(t("is too long (maximum is %d characters)"), 50) },
    })
    if data["source"] and not allowed_sources[data["source"]] then
      model_ext.add_error(errors, "source", t("Source"), t("is invalid"))
    end

    validate_field(errors, data, "grade_label", t("Grade label"), {
      { validation_ext.db_null_optional.string:maxlen(50), string.format(t("is too long (maximum is %d characters)"), 50) },
    })
    validate_field(errors, data, "responsibility_tier", t("Responsibility tier"), {
      { validation_ext.db_null_optional.string:maxlen(100), string.format(t("is too long (maximum is %d characters)"), 100) },
    })
    validate_field(errors, data, "deduplication_key", t("Deduplication key"), {
      { validation_ext.db_null_optional.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    })

    validate_number_range(errors, "score", t("Score"), data["score"], 0, 100)

    if (data["event_type"] == "grade" or data["event_type"] == "re_evaluate") and (data["score"] == nil or data["score"] == "" or data["score"] == db_null) then
      model_ext.add_error(errors, "score", t("Score"), t("can't be blank"))
    end

    if data["event_type"] == "responsibility_change" and (data["responsibility_tier"] == nil or data["responsibility_tier"] == "" or data["responsibility_tier"] == db_null) then
      model_ext.add_error(errors, "responsibility_tier", t("Responsibility tier"), t("can't be blank"))
    end

    for _, field_data in ipairs({
      { "evidence", t("Evidence") },
      { "outcome", t("Outcome") },
      { "metadata", t("Metadata") },
    }) do
      local field = field_data[1]
      local field_label = field_data[2]
      if data[field] and data[field] ~= db_null and not is_hash(data[field]) then
        model_ext.add_error(errors, field, field_label, t("unexpected type (must be a hash)"))
      end
    end

    if target and data["event_type"] and allowed_event_types[data["event_type"]] then
      if not allowed_transitions[target.state] or not allowed_transitions[target.state][data["event_type"]] then
        model_ext.add_error(errors, "event_type", t("Event type"), t("is not allowed for the target's current state"))
      end

      if data["event_type"] == "assigned" and self.id == nil then
        local existing = db.select("COUNT(*) AS c FROM agent_loop_events WHERE target_id = ?", target.id)
        if tonumber(existing[1]["c"]) > 0 then
          model_ext.add_error(errors, "event_type", t("Event type"), t("can only be recorded once"))
        end
      end
    end

    if data["deduplication_key"] and data["deduplication_key"] ~= db_null and data["deduplication_key"] ~= "" then
      model_ext.validate_uniqueness(errors, data, "deduplication_key", t("Deduplication key"), AgentLoopEvent, {
        "deduplication_key",
      })
    end

    return errors
  end,

  before_save = function(_, values)
    for _, field in ipairs({ "evidence", "outcome", "metadata" }) do
      if is_hash(values[field]) and values[field] ~= db_null then
        values[field] = db_raw(pg_encode_json(values[field]))
      end
    end
  end,

  after_save = function(self)
    local target = assert(AgentLoopTarget:find(self.target_id))
    local updates = build_target_updates(self, target)
    if next(updates) then
      assert(target:update(updates))
    end
  end,
})

AgentLoopEvent.for_target = function(target_id)
  return AgentLoopEvent:select("WHERE target_id = " .. db.escape_literal(target_id) .. " ORDER BY created_at ASC")
end

return AgentLoopEvent

local Admin = require "api-umbrella.web-app.models.admin"
local ApiUser = require "api-umbrella.web-app.models.api_user"
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

local allowed_states = {
  assigned = true,
  performed = true,
  evidenced = true,
  graded = true,
  responsibility_changed = true,
  re_evaluated = true,
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

local function validate_uuid_reference(errors, field, field_label, model, value)
  if value == nil or value == "" or value == db_null then
    return
  end

  if not validation_ext.string.uuid(value) then
    return
  end

  if not model:find(value) then
    model_ext.add_error(errors, field, field_label, t("is invalid"))
  end
end

local AgentLoopTarget = model_ext.new_class("agent_loop_targets", {
  as_json = function(self)
    return {
      id = json_null_default(self.id),
      agent_id = json_null_default(self.agent_id),
      name = json_null_default(self.name),
      description = json_null_default(self.description),
      state = json_null_default(self.state),
      mentor_admin_id = json_null_default(self.mentor_admin_id),
      responsibility_tier = json_null_default(self.responsibility_tier),
      current_grade = json_null_default(self.current_grade),
      current_grade_label = json_null_default(self.current_grade_label),
      reputation_score = json_null_default(self.reputation_score),
      asset_value = json_null_default(self.asset_value),
      last_event_at = json_null_default(time.postgres_to_iso8601(self.last_event_at)),
      iteration_count = json_null_default(self.iteration_count),
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
    if values["state"] == nil or values["state"] == "" or values["state"] == db_null then
      values["state"] = "assigned"
    end
    if values["responsibility_tier"] == nil or values["responsibility_tier"] == "" or values["responsibility_tier"] == db_null then
      values["responsibility_tier"] = "baseline"
    end
    if values["reputation_score"] == nil or values["reputation_score"] == "" or values["reputation_score"] == db_null then
      values["reputation_score"] = 0
    end
    if values["asset_value"] == nil or values["asset_value"] == "" or values["asset_value"] == db_null then
      values["asset_value"] = 0
    end
    if values["iteration_count"] == nil or values["iteration_count"] == "" or values["iteration_count"] == db_null then
      values["iteration_count"] = 0
    end
  end,

  before_validate = function(_, values)
    if values["current_grade"] ~= nil and values["current_grade"] ~= db_null and values["current_grade"] ~= "" then
      values["current_grade"] = tonumber(values["current_grade"]) or values["current_grade"]
    end
    if values["reputation_score"] ~= nil and values["reputation_score"] ~= db_null and values["reputation_score"] ~= "" then
      values["reputation_score"] = tonumber(values["reputation_score"]) or values["reputation_score"]
    end
    if values["asset_value"] ~= nil and values["asset_value"] ~= db_null and values["asset_value"] ~= "" then
      values["asset_value"] = tonumber(values["asset_value"]) or values["asset_value"]
    end
    if values["iteration_count"] ~= nil and values["iteration_count"] ~= db_null and values["iteration_count"] ~= "" then
      values["iteration_count"] = tonumber(values["iteration_count"]) or values["iteration_count"]
    end
  end,

  validate = function(_, data)
    local errors = {}

    validate_field(errors, data, "agent_id", t("Agent"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.string.uuid, t("is invalid") },
    })
    validate_uuid_reference(errors, "agent_id", t("Agent"), ApiUser, data["agent_id"])

    validate_field(errors, data, "name", t("Name"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.string:maxlen(255), string.format(t("is too long (maximum is %d characters)"), 255) },
    })

    validate_field(errors, data, "description", t("Description"), {
      { validation_ext.db_null_optional.string, t("is invalid") },
    })

    validate_field(errors, data, "responsibility_tier", t("Responsibility tier"), {
      { validation_ext.string:minlen(1), t("can't be blank") },
      { validation_ext.string:maxlen(100), string.format(t("is too long (maximum is %d characters)"), 100) },
    })

    if data["state"] and data["state"] ~= db_null and not allowed_states[data["state"]] then
      model_ext.add_error(errors, "state", t("State"), t("is invalid"))
    end

    validate_field(errors, data, "current_grade_label", t("Grade label"), {
      { validation_ext.db_null_optional.string:maxlen(50), string.format(t("is too long (maximum is %d characters)"), 50) },
    })

    validate_number_range(errors, "current_grade", t("Current grade"), data["current_grade"], 0, 100)

    if data["iteration_count"] ~= nil and data["iteration_count"] ~= db_null and data["iteration_count"] ~= "" then
      local iteration_count = tonumber(data["iteration_count"])
      if not iteration_count or iteration_count < 0 then
        model_ext.add_error(errors, "iteration_count", t("Iteration count"), t("is invalid"))
      end
    end

    if data["metadata"] and data["metadata"] ~= db_null and not is_hash(data["metadata"]) then
      model_ext.add_error(errors, "metadata", t("Metadata"), t("unexpected type (must be a hash)"))
    end

    validate_field(errors, data, "mentor_admin_id", t("Mentor"), {
      { validation_ext.db_null_optional.string, t("is invalid") },
    })
    if data["mentor_admin_id"] and data["mentor_admin_id"] ~= db_null and data["mentor_admin_id"] ~= "" and not validation_ext.string.uuid(data["mentor_admin_id"]) then
      model_ext.add_error(errors, "mentor_admin_id", t("Mentor"), t("is invalid"))
    end
    validate_uuid_reference(errors, "mentor_admin_id", t("Mentor"), Admin, data["mentor_admin_id"])

    return errors
  end,

  before_save = function(_, values)
    if is_hash(values["metadata"]) and values["metadata"] ~= db_null then
      values["metadata"] = db_raw(pg_encode_json(values["metadata"]))
    end
  end,
})

AgentLoopTarget.standings = function()
  local rows = db.query([[
    SELECT agent_loop_targets.agent_id,
      api_users.email,
      api_users.first_name,
      api_users.last_name,
      COUNT(*)::bigint AS target_count,
      COUNT(*) FILTER (WHERE agent_loop_targets.state IN ('assigned', 'performed', 'evidenced', 'graded', 're_evaluated', 'responsibility_changed'))::bigint AS active_target_count,
      ROUND(AVG(agent_loop_targets.current_grade), 2) AS average_grade,
      SUM(agent_loop_targets.reputation_score) AS reputation_score,
      SUM(agent_loop_targets.asset_value) AS asset_value,
      MAX(agent_loop_targets.last_event_at) AS last_event_at
    FROM agent_loop_targets
    JOIN api_users ON api_users.id = agent_loop_targets.agent_id
    GROUP BY agent_loop_targets.agent_id, api_users.email, api_users.first_name, api_users.last_name
    ORDER BY SUM(agent_loop_targets.reputation_score) DESC, MAX(agent_loop_targets.last_event_at) DESC NULLS LAST, api_users.email ASC
  ]])

  local standings = {}
  for _, row in ipairs(rows) do
    table.insert(standings, {
      agent_id = json_null_default(row.agent_id),
      email = json_null_default(row.email),
      first_name = json_null_default(row.first_name),
      last_name = json_null_default(row.last_name),
      target_count = json_null_default(tonumber(row.target_count)),
      active_target_count = json_null_default(tonumber(row.active_target_count)),
      average_grade = json_null_default(row.average_grade),
      reputation_score = json_null_default(row.reputation_score),
      asset_value = json_null_default(row.asset_value),
      last_event_at = json_null_default(time.postgres_to_iso8601(row.last_event_at)),
    })
  end

  return standings
end

return AgentLoopTarget

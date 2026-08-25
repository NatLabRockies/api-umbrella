local _M = {}

local function normalize_score(score)
  if type(score) ~= "number" then
    return nil
  end

  if score < 0 then
    return 0
  elseif score > 1 then
    return 1
  else
    return score
  end
end

local function grade_for_score(score)
  if score >= 0.9 then
    return "A"
  elseif score >= 0.8 then
    return "B"
  elseif score >= 0.7 then
    return "C"
  elseif score >= 0.6 then
    return "D"
  else
    return "F"
  end
end

function _M.evaluate(params)
  local normalized_score = normalize_score(params["score"])
  if normalized_score == nil then
    return nil, "invalid_score"
  end

  local normalized_target = normalize_score(params["target_score"])
  if normalized_target == nil then
    return nil, "invalid_target_score"
  end

  local passed = normalized_score >= normalized_target

  return {
    target = normalized_target,
    outcome_score = normalized_score,
    grade = grade_for_score(normalized_score),
    passed = passed,
    feedback = passed and "target_met" or "target_not_met",
    agent_value = normalized_score,
    asset_value = (normalized_score + normalized_target) / 2,
    reputation_delta = passed and 1 or -1,
    responsibility_change = passed and "increase_or_maintain" or "decrease_or_maintain",
  }
end

return _M

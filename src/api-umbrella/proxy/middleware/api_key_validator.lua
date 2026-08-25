local get_user = require("api-umbrella.proxy.stores.api_users_store").get

return function(ngx_ctx, settings)
  -- Retrieve the API key found in the resolve_api_key middleware.
  local api_key = ngx_ctx.api_key
  local api_key_method = ngx_ctx.api_key_method
  if not api_key then
    if settings and settings["disable_api_key"] then
      return nil
    else
      return nil, "api_key_missing"
    end
  end

  -- Look for the api key in the user database.
  local user = get_user(api_key)
  if not user then
    if settings and settings["disable_api_key"] and api_key_method == "basic_auth_username" then
      return nil
    end

    return nil, "api_key_invalid"
  end

  -- Store user details for logging.
  ngx_ctx.user_id = user["id"]
  ngx_ctx.user_email = user["email"]
  ngx_ctx.user_registration_source = user["registration_source"]

  -- Check to make sure the user isn't disabled.
  if user["disabled_at"] then
    return nil, "api_key_disabled"
  end

  -- Check if this API requires the user's API key be verified in some fashion
  -- (for example, if they must verify their e-mail address during signup).
  if settings and settings["api_key_verification_level"] then
    local verification_level = settings["api_key_verification_level"]
    if verification_level == "required_email" then
      if not user["email_verified"] then
        return nil, "api_key_unverified"
      end
    elseif verification_level == "transition_email" then
      local transition_start_at = settings["_api_key_verification_transition_start_at"]
      if user["created_at"] and user["created_at"] >= transition_start_at and not user["email_verified"] then
        return nil, "api_key_unverified"
      end
    end
  end

  return user
end

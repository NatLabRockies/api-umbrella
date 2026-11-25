local shared_dict_retry_set = require("api-umbrella.utils.shared_dict_retry").set
local worker_group = require "api-umbrella.utils.worker_group"

local active_config_dict = ngx.shared.active_config
local jobs_dict = ngx.shared.jobs
local worker_group_is_latest = worker_group.is_latest
local worker_group_needs_config_refresh = worker_group.needs_config_refresh

return function(cache, callback)
  -- If this worker process isn't part of the latest group, then don't perform
  -- any further processing. This prevents older workers that may be in the
  -- process of shutting down after a SIGHUP reload from performing a check and
  -- possibly overwriting newer config (since the file config is only read in
  -- on SIGHUPs and may differ between the older and newer worker groups).
  if not worker_group_is_latest() then
    return
  end

  -- Get the latest version fetched from the database so we can look for newer
  -- versions during polling.
  local last_fetched_version, last_fetched_version_err = jobs_dict:get("active_config_store_last_fetched_version")
  if last_fetched_version_err then
    ngx.log(ngx.ERR, "Error fetching last_fetched_version: ", last_fetched_version_err)
    return
  end

  -- If this set of worker processes hasn't been setup yet (initial boot or
  -- after reload), force a re-fetch of the latest database config so that any
  -- updated file config also gets read in. By setting last_fetched_version to
  -- nil, the fetch callback will look for any version and process it like the
  -- very first fetch.
  if worker_group_needs_config_refresh() then
    last_fetched_version = nil
  end

  local new_active_config_value = callback(last_fetched_version)
  if new_active_config_value then
    local key = "active_config"
    local namespaced_key = cache.ns_prefix .. key

    local previous_active_config_value, previous_get_err = active_config_dict:get(namespaced_key)
    if previous_get_err then
      ngx.log(ngx.ERR, "Error fetching previous active_config: ", previous_get_err)
    end

    -- We originally bailed if this wasn't part of the latest worker group (see
    -- above), but it's possible between the time this method started and the
    -- time we got here that this has changed, so do another sanity check before
    -- setting the active config.
    local is_latest = worker_group_is_latest()
    if not is_latest then
      return
    end

    local set_ok, set_err = cache:set(key, nil, new_active_config_value)
    if not set_ok then
      ngx.log(ngx.ERR, "Error setting active_config: ", set_err)

      -- If the new config exceeds the amount of available space, or any other
      -- error occurs, then revert the shared dict config back to the previous
      -- version.
      --
      -- Since this occurs after active_config_store_last_fetched_version is
      -- updated (which happens as part of the new config being generated in
      -- fetch_published_config_for_setting_active_config), then polling will
      -- no longer look for this newer version. This prevents the system from
      -- looping indefinitely and trying to set the config over and over to a
      -- version that won't fit in memory. No solution is really great here,
      -- since the shdict memory needs to be increased.
      --
      -- Also note that this can't be solved by safe_set (although mlcache does
      -- not use that), since that still requires this type of workaround:
      -- https://github.com/openresty/lua-nginx-module/issues/1365
      if previous_active_config_value then
        local previous_set_ok, previous_set_err, previous_set_forcible = shared_dict_retry_set(active_config_dict, namespaced_key, previous_active_config_value)
        if not previous_set_ok then
          ngx.log(ngx.ERR, "failed to set 'active_config' in 'active_config' shared dict: ", previous_set_err)
        elseif previous_set_forcible then
          ngx.log(ngx.WARN, "forcibly set 'active_config' in 'active_config' shared dict (shared dict may be too small)")
        end

        ngx.log(ngx.ERR, "Reverted active_config back to previous version after setting new version failed")
      end
    end
  end
end

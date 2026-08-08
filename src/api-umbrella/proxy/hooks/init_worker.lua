local active_config_store_poll_for_update = require "api-umbrella.proxy.jobs.active_config_store_poll_for_update"
local active_config_store_refresh_local_cache = require "api-umbrella.proxy.jobs.active_config_store_refresh_local_cache"
local api_users_store_delete_stale_cache = require "api-umbrella.proxy.jobs.api_users_store_delete_stale_cache"
local api_users_store_refresh_local_cache = require "api-umbrella.proxy.jobs.api_users_store_refresh_local_cache"
local db_expirations = require "api-umbrella.proxy.jobs.db_expirations"
local distributed_rate_limit_puller = require "api-umbrella.proxy.jobs.distributed_rate_limit_puller"
local distributed_rate_limit_pusher = require "api-umbrella.proxy.jobs.distributed_rate_limit_pusher"
local opensearch_setup = require "api-umbrella.proxy.startup.opensearch_setup"
local random_seed = require "api-umbrella.utils.random_seed"
local seed_database = require "api-umbrella.proxy.startup.seed_database"

-- random_seed may have been been called during the "init" hook as a result of
-- pre-loading modules, but we want to ensure each worker process's random seed
-- is different, so force another call in the init_worker phase.
random_seed()

active_config_store_poll_for_update.spawn()
active_config_store_refresh_local_cache.spawn()
api_users_store_delete_stale_cache.spawn()
api_users_store_refresh_local_cache.spawn()
db_expirations.spawn()
distributed_rate_limit_puller.spawn()
distributed_rate_limit_pusher.spawn()
opensearch_setup.spawn()
seed_database.spawn()

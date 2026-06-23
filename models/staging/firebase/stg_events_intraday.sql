{{
  config(
    materialized='incremental',
    partition_by={'field': 'event_date', 'data_type': 'date'},
    cluster_by=['event_name', 'user_pseudo_id'],
    incremental_strategy='insert_overwrite'
  )
}}

-- Today's streaming events from Firebase events_intraday_YYYYMMDD.
--
-- Behavior:
--   On every run: insert_overwrite replaces today's partition with the
--   latest snapshot from events_intraday_YYYYMMDD. Idempotent and safe
--   to run as often as needed.
--   Tomorrow this data is replaced by the finalized version in stg_events_daily.
--
-- Recommended schedule: every 15 minutes
--   dbt run --select stg_events_intraday

SELECT
  PARSE_DATE('%Y%m%d', event_date)                                          AS event_date,
  TIMESTAMP_MICROS(event_timestamp)                                         AS event_timestamp,
  event_name,
  event_value_in_usd,
  user_pseudo_id,
  TIMESTAMP_MICROS(user_first_touch_timestamp)                              AS user_first_touch_timestamp,

  device.category                                                           AS device_category,
  device.mobile_brand_name                                                  AS device_mobile_brand_name,
  device.mobile_model_name                                                  AS device_mobile_model_name,
  device.mobile_marketing_name                                              AS device_mobile_marketing_name,
  device.mobile_os_hardware_model                                           AS device_mobile_os_hardware_model,
  device.operating_system                                                   AS device_operating_system,
  device.operating_system_version                                           AS device_operating_system_version,
  device.language                                                           AS device_language,
  device.is_limited_ad_tracking                                             AS device_is_limited_ad_tracking,
  device.time_zone_offset_seconds                                           AS device_time_zone_offset_seconds,

  geo.continent                                                             AS geo_continent,
  geo.country                                                               AS geo_country,
  geo.region                                                                AS geo_region,
  geo.city                                                                  AS geo_city,
  geo.sub_continent                                                         AS geo_sub_continent,
  geo.metro                                                                 AS geo_metro,

  app_info.id                                                               AS app_info_id,
  app_info.version                                                          AS app_version,
  app_info.install_store                                                    AS app_info_install_store,
  app_info.firebase_app_id                                                  AS app_info_firebase_app_id,
  app_info.install_source                                                   AS app_info_install_source,

  traffic_source.name                                                       AS traffic_source_name,
  traffic_source.medium                                                     AS traffic_source_medium,
  traffic_source.source                                                     AS traffic_source_source,

  stream_id,
  platform,

  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'booster_id')           AS booster_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'day_num')              AS day_num,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'doubleReward')         AS double_reward,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances')            AS entrances,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'firebase_conversion')  AS firebase_conversion,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'food_id')              AS food_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')        AS ga_session_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number')    AS ga_session_number,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'gem_cost')             AS gem_cost,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'level_id')             AS level_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'level_num')            AS level_num,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'newAvatarId')          AS new_avatar_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'object_id')            AS object_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'object_level')         AS object_level,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'price')                AS price,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'price_gems')           AS price_gems,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'quantity')             AS quantity,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'quest_id')             AS quest_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'refresh')              AS refresh,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'reward_amount')        AS reward_amount,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'staff_id')             AS staff_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'staff_level')          AS staff_level,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'step_num')             AS step_num,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'time')                 AS time,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'timestamp')            AS param_timestamp,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'tutorial_id')          AS tutorial_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'validated')            AS validated,
  CAST(COALESCE(
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'value'),
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
  ) AS FLOAT64)                                                                          AS param_value,

  CAST(COALESCE(
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'amount'),
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'amount')
  ) AS FLOAT64)                                                                          AS amount,
  (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'price_dollars')     AS price_dollars,
  (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'time_spent')        AS time_spent,

  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ad')                AS ad,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'currency')          AS currency,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'currency_type')     AS currency_type,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'event_name')        AS param_event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'firebase_event_origin') AS firebase_event_origin,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'from_screen')       AS from_screen,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name')         AS item_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'location')          AS location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'newName')           AS new_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'object_name')       AS object_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'placement')         AS placement,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'product_id')        AS product_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'product_name')      AS product_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'reason')            AS reason,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'reward_type')       AS reward_type,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source')            AS param_source,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'status')            AS status,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'to_screen')         AS to_screen,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'type')              AS type,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'with_ads')          AS with_ads,
  user_id
{#
  Never use events_intraday_* in compiled SQL: dbt Fusion caches sourced_remote schemas
  under target/.lsp using the table id; '*' is illegal in Windows paths (dbt1016).
  Today's shard is sufficient for intraday (same rows as wildcard + _TABLE_SUFFIX).
#}
{% set _intraday_src = source('firebase_analytics', 'events_intraday_wildcard') %}
{% set _intraday_suffix = run_started_at.strftime('%Y%m%d') %}
FROM
  `{{ _intraday_src.database }}`.`{{ _intraday_src.schema }}`.`events_intraday_{{ _intraday_suffix }}`
WHERE
  event_date = FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name IN (
    'ad_impression', 'ad_rewarded', 'booster_used',
    'challenge_change_settings', 'challenge_event', 'challenge_quit',
    'challenge_resume', 'challenge_returned_lost_customer', 'challenge_time_added',
    'change_settings',
    'claim_all_mission_rewards', 'claim_last_welcome_quest_reward',
    'claim_mission_reward', 'claim_season_reward', 'claim_welcome_quest_reward',
    'currency_earned', 'currency_spent', 'daily_reward_claimed',
    'delivery_dash_accept_order', 'delivery_dash_collect_reward',
    'delivery_dash_get_new_orders', 'delivery_dash_instant_finish',
    'delivery_dash_reject_order', 'delivery_restock_food',
    'edit_profile_avatar', 'edit_profile_name',
    'first_open', 'game_started',
    'iap_purchase', 'iap_purchase_failed', 'in_app_purchase',
    'level_completed', 'level_failed', 'level_started',
    'new_player', 'object_level_purchase', 'refresh_quest',
    'screen_change', 'screen_view', 'session_start',
    'staff_level_purchase', 'tutorial_completed', 'tutorial_step',
    'user_engagement'
  )

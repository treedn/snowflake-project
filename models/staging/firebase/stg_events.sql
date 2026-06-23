{{
  config(
    materialized='view'
  )
}}

-- Unified events view: finalized history + today's intraday.
--
-- This is the table downstream models and analyses should query.
-- It's a view -- no storage cost, always reflects the latest data
-- from both stg_events_daily and stg_events_intraday.
--
-- Explicit column list (not SELECT *): dbt Fusion resolves SELECT * from refs
-- using per-source BigQuery schemas; daily vs intraday shards can differ in width
-- even though both models project the same fields — UNION ALL then fails dbt0301.

{% set event_cols %}
  event_date,
  event_timestamp,
  event_name,
  event_value_in_usd,
  user_pseudo_id,
  user_first_touch_timestamp,
  device_category,
  device_mobile_brand_name,
  device_mobile_model_name,
  device_mobile_marketing_name,
  device_mobile_os_hardware_model,
  device_operating_system,
  device_operating_system_version,
  device_language,
  device_is_limited_ad_tracking,
  device_time_zone_offset_seconds,
  geo_continent,
  geo_country,
  geo_region,
  geo_city,
  geo_sub_continent,
  geo_metro,
  app_info_id,
  app_version,
  app_info_install_store,
  app_info_firebase_app_id,
  app_info_install_source,
  traffic_source_name,
  traffic_source_medium,
  traffic_source_source,
  stream_id,
  platform,
  booster_id,
  day_num,
  double_reward,
  engagement_time_msec,
  entrances,
  firebase_conversion,
  food_id,
  ga_session_id,
  ga_session_number,
  gem_cost,
  level_id,
  level_num,
  new_avatar_id,
  object_id,
  object_level,
  price,
  price_gems,
  quantity,
  quest_id,
  refresh,
  reward_amount,
  staff_id,
  staff_level,
  step_num,
  `time`,
  param_timestamp,
  tutorial_id,
  validated,
  param_value,
  amount,
  price_dollars,
  time_spent,
  ad,
  currency,
  currency_type,
  param_event_name,
  firebase_event_origin,
  from_screen,
  item_name,
  location,
  new_name,
  object_name,
  placement,
  product_id,
  product_name,
  reason,
  reward_type,
  param_source,
  status,
  to_screen,
  `type`,
  with_ads,
  user_id
{% endset %}

SELECT
{{ event_cols }}
FROM {{ ref('stg_events_daily') }}

UNION ALL

SELECT
{{ event_cols }}
FROM {{ ref('stg_events_intraday') }}

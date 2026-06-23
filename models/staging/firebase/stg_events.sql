{{
  config(
    materialized='table',
    partition_by={'field': 'event_date', 'data_type': 'date'},
    cluster_by=['event_name', 'user_pseudo_id']
  )
}}

-- Unified events table: finalized history + today's intraday, plus
-- forward-filled level_id and the user's previous/next distinct level.
--
-- Materialized as a table (not a view) so window functions over each
-- user's full event history run once per dbt run instead of per query.
-- At ~10K events/day, full-refresh is cheap.
--
-- Column semantics:
--   level_id          : forward-filled per user (last non-null level_id at or
--                       before this row). Stays NULL until the user's first
--                       level event; subsequent rows carry the current level
--                       until the next level_id change.
--   previous_level_id : the user's previous *distinct* level before the
--                       current one. NULL on the user's first level run.
--   next_level_id     : the user's next *distinct* level after the current
--                       one. NULL on the user's final level run.
--
-- Explicit column list (not SELECT *) on the UNION ALL: dbt Fusion resolves
-- SELECT * from refs using per-source BigQuery schemas; daily vs intraday
-- shards can differ in width even though both models project the same
-- fields — UNION ALL then fails dbt0301.

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

WITH unioned AS (
  SELECT {{ event_cols }} FROM {{ ref('stg_events_daily') }}
  UNION ALL
  SELECT {{ event_cols }} FROM {{ ref('stg_events_intraday') }}
),

filled AS (
  -- Forward-fill level_id per user. Overwrites the original column;
  -- rows that arrive before the user's first level event remain NULL.
  SELECT
    * EXCEPT (level_id),
    LAST_VALUE(level_id IGNORE NULLS) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS level_id
  FROM unioned
),

runs_marked AS (
  -- Flag rows where level_id changes (start of a new run).
  -- Split out from the cumulative sum below because BigQuery does not
  -- allow nesting analytic functions inside another analytic function.
  SELECT
    *,
    CASE
      WHEN level_id IS DISTINCT FROM LAG(level_id) OVER (
        PARTITION BY user_pseudo_id ORDER BY event_timestamp
      ) THEN 1
      ELSE 0
    END AS is_run_start
  FROM filled
),

runs AS (
  -- Number each consecutive run of identical level_id per user.
  SELECT
    * EXCEPT (is_run_start),
    SUM(is_run_start) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS level_run_id
  FROM runs_marked
),

run_levels AS (
  -- One row per (user, level run) carrying that run's level_id.
  SELECT DISTINCT user_pseudo_id, level_run_id, level_id
  FROM runs
),

run_neighbors AS (
  -- Previous/next distinct level for each run.
  SELECT
    user_pseudo_id,
    level_run_id,
    LAG(level_id) OVER (PARTITION BY user_pseudo_id ORDER BY level_run_id) AS previous_level_id,
    LEAD(level_id) OVER (PARTITION BY user_pseudo_id ORDER BY level_run_id) AS next_level_id
  FROM run_levels
)

SELECT
  r.* EXCEPT (level_run_id),
  n.previous_level_id,
  n.next_level_id
FROM runs r
JOIN run_neighbors n USING (user_pseudo_id, level_run_id)

{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'date', 'data_type': 'date'},
    cluster_by=['tutorial_id', 'app_version', 'geo_country'],
    on_schema_change='append_new_columns'
) }}

-- Daily tutorial funnel at (date, app_version, geo_country, platform,
-- tutorial_id, step_num). Source: stg_events (Firebase).
--
-- Long format. One row per cell.
--   step_num = 1..N : a `tutorial_step` event at step N of this tutorial_id.
--   step_num = NULL : a `tutorial_completed` event for this tutorial_id.
--
-- Measures:
--   users  : COUNT(DISTINCT user_pseudo_id) per cell.
--   events : raw event count per cell (for sanity / repeat-fire diagnostics —
--            users typically < events because some users replay a step).
--
-- Recipes:
--   #1 FTUE / per-tutorial completion rate (last 14d):
--      SELECT tutorial_id,
--             SUM(IF(step_num = 1,    users, 0)) AS users_started,
--             SUM(IF(step_num IS NULL, users, 0)) AS users_completed,
--             SAFE_DIVIDE(SUM(IF(step_num IS NULL, users, 0)),
--                         NULLIF(SUM(IF(step_num = 1, users, 0)), 0))
--               AS completion_rate
--      FROM marts.tutorial_funnel_daily
--      WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
--      GROUP BY tutorial_id;
--
--   #2 Drop-off curve for a tutorial:
--      SELECT step_num, SUM(users) AS users
--      FROM marts.tutorial_funnel_daily
--      WHERE tutorial_id = 40000
--        AND step_num IS NOT NULL
--        AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
--      GROUP BY step_num
--      ORDER BY step_num;
--
-- Caveats:
-- - "Started" anchor is step_num = 1. A small number of sessions fire
--   step_num >= 2 without step_num = 1 (mid-tutorial join / event loss);
--   completion_rate using step 1 as denominator is an upper bound.
-- - `users` is exact within a cell. Summing across cells (e.g. across
--   app_versions or geos) double-counts users who span cells — same caveat
--   as engagement_daily. For exact cross-cell rates, recompute from
--   stg_events at user grain.
-- - Spans of `tutorial_id` between 40000–40022 represent real tutorials.
--   Game-team tutorial naming is not in this layer; map via the design doc
--   or join an external tutorial-id sheet.
-- - Croatia excluded (consistent with iap_arpdau_daily / cohort_ltv_daily /
--   session_depth_daily).
-- - Incremental: rebuilds the last 14 days each run.

with events_in_window as (
  select
    e.event_date                       as date,
    coalesce(e.app_version, 'unknown') as app_version,
    coalesce(e.geo_country, 'unknown') as geo_country,
    coalesce(e.platform,    'unknown') as platform,
    e.tutorial_id,
    case
      when e.event_name = 'tutorial_step' then e.step_num
      else null
    end                                as step_num,
    e.user_pseudo_id
  from {{ ref('stg_events') }} e
  where e.event_name in ('tutorial_step', 'tutorial_completed')
    and e.user_pseudo_id is not null
    and e.tutorial_id    is not null
    and e.geo_country    != 'Croatia'
    {% if is_incremental() %}
    and e.event_date >= date_sub(current_date(), interval 14 day)
    {% endif %}
)

select
  date,
  app_version,
  geo_country,
  platform,
  tutorial_id,
  step_num,
  count(distinct user_pseudo_id) as users,
  count(*)                       as events
from events_in_window
group by 1, 2, 3, 4, 5, 6

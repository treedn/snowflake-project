{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'date', 'data_type': 'date'},
    cluster_by=['platform', 'app_version', 'geo_country'],
    on_schema_change='append_new_columns'
) }}

-- Daily session-depth distribution at (date, platform, app_version, geo_country).
-- Source: stg_events (Firebase).
--
-- One row per (date, platform, app_version, geo_country) with distribution
-- summaries (avg + p25/p50/p75/p90/p99) for four metrics:
--
--   events_per_session   : meaningful events per (user_pseudo_id, ga_session_id),
--                          EXCLUDING Firebase-auto noise:
--                            user_engagement, screen_change, screen_view
--   duration_seconds     : max(event_timestamp) - min(event_timestamp) per
--                          session, computed over ALL events including noise so
--                          the session window is accurate even when only
--                          auto-fired events occur.
--   levels_per_session   : count(distinct level_id) on level_started events
--                          within the session.
--   sessions_per_user    : count(distinct ga_session_id) per (user, date) cell.
--                          A user with sessions across multiple cells in one
--                          day contributes one row per cell (so platform-level
--                          rollups remain consistent).
--
-- Session attribution: a session = (user_pseudo_id, ga_session_id), assigned to
-- the date of its FIRST event. Sessions that span midnight count once, on the
-- start date.
--
-- Cell attribution: platform/app_version/geo_country are taken via ANY_VALUE
-- on the session's events. These dims are typically constant within a session.
--
-- Croatia is excluded (consistent with iap_arpdau_daily / cohort_ltv_daily).
-- Incremental: rebuilds the last 14 days each run. Sessions whose first event
-- predates the window are partially aggregated, which is acceptable since
-- gameplay sessions in this app are intra-day.

with events_in_window as (
  select
    e.event_date,
    e.event_timestamp,
    e.event_name,
    e.user_pseudo_id,
    e.ga_session_id,
    e.level_id,
    coalesce(e.platform,    'unknown') as platform,
    coalesce(e.app_version, 'unknown') as app_version,
    coalesce(e.geo_country, 'unknown') as geo_country
  from {{ ref('stg_events') }} e
  where e.user_pseudo_id is not null
    and e.ga_session_id  is not null
    and e.geo_country != 'Croatia'
    {% if is_incremental() %}
    and e.event_date >= date_sub(current_date(), interval 14 day)
    {% endif %}
),

sessions as (
  select
    user_pseudo_id,
    ga_session_id,
    min(event_date)                                                              as session_date,
    any_value(platform)                                                          as platform,
    any_value(app_version)                                                       as app_version,
    any_value(geo_country)                                                       as geo_country,
    countif(event_name not in ('user_engagement','screen_change','screen_view')) as events_in_session,
    timestamp_diff(max(event_timestamp), min(event_timestamp), second)           as duration_seconds,
    count(distinct if(event_name = 'level_started', level_id, null))             as levels_in_session
  from events_in_window
  group by user_pseudo_id, ga_session_id
),

user_days as (
  select
    session_date as date,
    platform,
    app_version,
    geo_country,
    user_pseudo_id,
    count(distinct ga_session_id) as sessions_in_day
  from sessions
  group by date, platform, app_version, geo_country, user_pseudo_id
),

session_aggs as (
  select
    session_date as date,
    platform,
    app_version,
    geo_country,

    count(*) as sessions,

    avg(events_in_session)                                    as avg_events_per_session,
    approx_quantiles(events_in_session, 100)[offset(25)]      as p25_events_per_session,
    approx_quantiles(events_in_session, 100)[offset(50)]      as p50_events_per_session,
    approx_quantiles(events_in_session, 100)[offset(75)]      as p75_events_per_session,
    approx_quantiles(events_in_session, 100)[offset(90)]      as p90_events_per_session,
    approx_quantiles(events_in_session, 100)[offset(99)]      as p99_events_per_session,

    avg(duration_seconds)                                     as avg_duration_seconds,
    approx_quantiles(duration_seconds, 100)[offset(25)]       as p25_duration_seconds,
    approx_quantiles(duration_seconds, 100)[offset(50)]       as p50_duration_seconds,
    approx_quantiles(duration_seconds, 100)[offset(75)]       as p75_duration_seconds,
    approx_quantiles(duration_seconds, 100)[offset(90)]       as p90_duration_seconds,
    approx_quantiles(duration_seconds, 100)[offset(99)]       as p99_duration_seconds,

    avg(levels_in_session)                                    as avg_levels_per_session,
    approx_quantiles(levels_in_session, 100)[offset(25)]      as p25_levels_per_session,
    approx_quantiles(levels_in_session, 100)[offset(50)]      as p50_levels_per_session,
    approx_quantiles(levels_in_session, 100)[offset(75)]      as p75_levels_per_session,
    approx_quantiles(levels_in_session, 100)[offset(90)]      as p90_levels_per_session,
    approx_quantiles(levels_in_session, 100)[offset(99)]      as p99_levels_per_session
  from sessions
  group by 1, 2, 3, 4
),

user_day_aggs as (
  select
    date,
    platform,
    app_version,
    geo_country,

    count(*) as user_days,

    avg(sessions_in_day)                                      as avg_sessions_per_user,
    approx_quantiles(sessions_in_day, 100)[offset(25)]        as p25_sessions_per_user,
    approx_quantiles(sessions_in_day, 100)[offset(50)]        as p50_sessions_per_user,
    approx_quantiles(sessions_in_day, 100)[offset(75)]        as p75_sessions_per_user,
    approx_quantiles(sessions_in_day, 100)[offset(90)]        as p90_sessions_per_user,
    approx_quantiles(sessions_in_day, 100)[offset(99)]        as p99_sessions_per_user
  from user_days
  group by 1, 2, 3, 4
)

select
  s.date,
  s.platform,
  s.app_version,
  s.geo_country,

  s.sessions,
  ud.user_days,

  s.avg_events_per_session,
  s.p25_events_per_session,
  s.p50_events_per_session,
  s.p75_events_per_session,
  s.p90_events_per_session,
  s.p99_events_per_session,

  s.avg_duration_seconds,
  s.p25_duration_seconds,
  s.p50_duration_seconds,
  s.p75_duration_seconds,
  s.p90_duration_seconds,
  s.p99_duration_seconds,

  s.avg_levels_per_session,
  s.p25_levels_per_session,
  s.p50_levels_per_session,
  s.p75_levels_per_session,
  s.p90_levels_per_session,
  s.p99_levels_per_session,

  ud.avg_sessions_per_user,
  ud.p25_sessions_per_user,
  ud.p50_sessions_per_user,
  ud.p75_sessions_per_user,
  ud.p90_sessions_per_user,
  ud.p99_sessions_per_user
from session_aggs s
left join user_day_aggs ud
  using (date, platform, app_version, geo_country)

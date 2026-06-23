{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'cohort_date', 'data_type': 'date'},
    cluster_by=['geo_country', 'app_version', 'days_since_install'],
    on_schema_change='append_new_columns'
) }}

-- Daily IAP cohort LTV components at
-- (cohort_date, days_since_install, geo_country, app_version).
-- Source: stg_events (Firebase).
--
-- Stores summable numerators (iap_revenue, iap_transactions, paying_users) and
-- the denominator (cohort_size) so consumers recompute the LTV curve correctly:
--   cumulative_ltv(N) = SUM(iap_revenue WHERE days_since_install <= N)
--                       / cohort_size
-- Don't pre-aggregate cumulative_ltv into the mart — it's not summable across
-- cohorts, and storing only the per-DSI components keeps every checkpoint
-- (D7, D14, D30, etc.) reachable from a single SUM-and-divide.
--
-- Cohort definition:
--   cohort_date = first event_date where event_name = 'first_open' per
--                 user_pseudo_id. (Note: `analytics.retention_cohorts` uses
--                 first_open OR new_player; this mart uses first_open only,
--                 so cohort sizes can be marginally smaller for users where
--                 new_player fired before first_open.)
--   geo_country = geo on that cohort event, coalesced to 'unknown'.
--   app_version = app_version on that cohort event, coalesced to 'unknown'.
-- Both dims are frozen at install — a user who upgrades 0.10 -> 0.11 stays in
-- the 0.10 cohort.
--
-- IAP revenue:
--   sum of coalesce(event_value_in_usd, price_dollars, 0) on
--   (iap_purchase, in_app_purchase) events. Matches `iap_arpdau_daily`.
--   The generic `amount` event param is deliberately excluded — it carries
--   currency_earned/spent coin amounts on non-IAP events and would inflate
--   totals by orders of magnitude. (This is the bug currently in
--   `analytics.retention_cohorts.total_iap_value_usd`.)
--
-- Ad revenue is NOT in this mart. Firebase ad events carry no $ value. For
-- ad-revenue cohort LTV, use Adjust cohort revenue (not currently ingested
-- into this layer).
--
-- Croatia is excluded at install — users whose cohort event is geo=Croatia
-- never enter the mart.
--
-- Curve horizon: days_since_install in [0, max_dsi]. A (cohort_date, dsi) row
-- is only emitted once the calendar day at cohort_date + dsi has fully
-- elapsed (strict `< current_date()`), so partial-day rows can't sneak into
-- aggregations.
--
-- Incremental: rebuilds cohort_date partitions where
--   cohort_date >= current_date() - (max_dsi + lag_days)
-- The lag_days buffer matches the 14-day refresh window on the other marts —
-- it absorbs Firebase event-arrival lag. Older cohort partitions are frozen
-- until `dbt run --full-refresh`.

{% set max_dsi = 30 %}
{% set lag_days = 14 %}

with first_cohort_event as (
  select
    user_pseudo_id,
    event_date,
    coalesce(geo_country, 'unknown') as geo_country,
    coalesce(app_version, 'unknown') as app_version,
    row_number() over (
      partition by user_pseudo_id
      order by event_timestamp
    ) as rn
  from {{ ref('stg_events') }}
  where event_name in ('first_open')
    and user_pseudo_id is not null
    and geo_country != 'Croatia'
    {% if is_incremental() %}
    and event_date >= date_sub(current_date(), interval {{ max_dsi + lag_days }} day)
    {% endif %}
),

cohort_assignments as (
  select
    user_pseudo_id,
    event_date as cohort_date,
    geo_country,
    app_version
  from first_cohort_event
  where rn = 1
),

cohort_sizes as (
  select
    cohort_date,
    geo_country,
    app_version,
    count(distinct user_pseudo_id) as cohort_size
  from cohort_assignments
  group by 1, 2, 3
),

iap_events_by_dsi as (
  select
    c.cohort_date,
    c.geo_country,
    c.app_version,
    date_diff(e.event_date, c.cohort_date, day) as days_since_install,
    c.user_pseudo_id,
    coalesce(e.event_value_in_usd, e.price_dollars, 0) as event_value_usd
  from cohort_assignments c
  join {{ ref('stg_events') }} e using (user_pseudo_id)
  where e.event_name in ('iap_purchase', 'in_app_purchase')
    and coalesce(e.event_value_in_usd, e.price_dollars, 0) > 0
    and date_diff(e.event_date, c.cohort_date, day) between 0 and {{ max_dsi }}
    {% if is_incremental() %}
    and e.event_date >= date_sub(current_date(), interval {{ max_dsi + lag_days }} day)
    {% endif %}
),

iap_per_dsi as (
  select
    cohort_date,
    geo_country,
    app_version,
    days_since_install,
    sum(event_value_usd)           as iap_revenue,
    count(*)                       as iap_transactions,
    count(distinct user_pseudo_id) as paying_users
  from iap_events_by_dsi
  group by 1, 2, 3, 4
),

day_grid as (
  select
    cs.cohort_date,
    cs.geo_country,
    cs.app_version,
    cs.cohort_size,
    dsi as days_since_install
  from cohort_sizes cs,
       unnest(generate_array(0, {{ max_dsi }})) as dsi
)

select
  g.cohort_date,
  g.days_since_install,
  g.geo_country,
  g.app_version,
  g.cohort_size,
  coalesce(i.iap_revenue, 0)      as iap_revenue,
  coalesce(i.iap_transactions, 0) as iap_transactions,
  coalesce(i.paying_users, 0)     as paying_users
from day_grid g
left join iap_per_dsi i
  using (cohort_date, geo_country, app_version, days_since_install)
where date_add(g.cohort_date, interval g.days_since_install day) < current_date()

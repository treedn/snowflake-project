{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'date', 'data_type': 'date'},
    cluster_by=['geo_country', 'app_version', 'spender_segment'],
    on_schema_change='append_new_columns'
) }}

-- Daily IAP revenue + ARPDAU at (date, geo_country, app_version, spender_segment).
-- Source: stg_events (Firebase).
--
-- Complements `ua_performance_daily` (Adjust-sourced, IAP + ad split, geo +
-- network grain). This mart owns the segmentation that Adjust can't supply:
-- app_version (not in Adjust groupBy) and spender_segment (per-user concept).
--
-- IAP revenue = SUM of `event_value_in_usd` and `price_dollars` on
-- (`iap_purchase`, `in_app_purchase`) events ONLY. The generic `amount` event
-- param is intentionally excluded — it carries currency_earned/spent coin
-- amounts on non-IAP events and would massively inflate totals if summed
-- (this is the bug currently in `analytics.retention_cohorts.total_iap_value_usd`).
--
-- Ad revenue is NOT in this mart. Firebase `ad_impression` /
-- `ad_rewarded` events do not currently carry $ values (verified empty across
-- event_value_in_usd, price_dollars, amount, param_value, price, reward_amount).
-- For ad revenue at any grain, use `ua_performance_daily` (Adjust scope).
--
-- spender_segment = 'spender' if user has any IAP > 0 in `stg_events` history,
-- else 'non_spender'. The lookup is full-history each run, so a user who first
-- spends today gets reclassified as 'spender' across all their prior rows on
-- the next incremental rebuild — that is, the mart reflects spender status
-- "as of run time", not "as of event_date".
--
-- Incremental: rebuilds the last 14 days each run.

with spender_lookup as (
  select
    user_pseudo_id,
    case when max(case
      when {{ is_iap_revenue_event() }}
      then 1 else 0 end) = 1
    then 'spender' else 'non_spender' end as spender_segment
  from {{ ref('stg_events') }}
  where user_pseudo_id is not null
  group by 1
),

events_in_window as (
  select
    e.event_date,
    coalesce(e.geo_country, 'unknown')         as geo_country,
    coalesce(e.app_version, 'unknown')         as app_version,
    coalesce(s.spender_segment, 'non_spender') as spender_segment,
    e.user_pseudo_id,
    e.event_name,
    e.event_value_in_usd,
    e.price_dollars
  from {{ ref('stg_events') }} e
  left join spender_lookup s using(user_pseudo_id)
  where e.user_pseudo_id is not null
    and e.geo_country != 'Croatia'
    {% if is_incremental() %}
    and e.event_date >= date_sub(current_date(), interval 14 day)
    {% endif %}
)

select
  event_date                                                    as date,
  geo_country,
  app_version,
  spender_segment,

  count(distinct user_pseudo_id)                                as dau,

  sum(case
    when event_name in {{ iap_event_names() }}
    then {{ iap_value_usd() }}
    else 0
  end)                                                          as iap_revenue,

  countif({{ is_iap_revenue_event() }})                         as iap_transactions,

  safe_divide(
    sum(case
      when event_name in {{ iap_event_names() }}
      then {{ iap_value_usd() }}
      else 0
    end),
    nullif(count(distinct user_pseudo_id), 0)
  )                                                             as arpdau_iap

from events_in_window
group by 1, 2, 3, 4

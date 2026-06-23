{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'date', 'data_type': 'date'},
    cluster_by=['country', 'platform'],
    on_schema_change='append_new_columns'
) }}

-- Player engagement from Unity Analytics, rolled up from clientVersion.
-- Caveat: Unity returns DAU/payers/sessions per breakdown row; users on multiple
-- clientVersions in a day are counted in each. The sums below are upper bounds.
-- Retention/ARPDAU rates are weighted by DAU to keep them comparable to Unity's
-- own dashboard. Re-pull unity_data_gateway without `clientVersion` in groupBy
-- to get exact totals.
-- Incremental: rebuild last 14 days each run.
with src as (
  select * from {{ ref('stg_unity__analytics_daily') }}
  {% if is_incremental() %}
  where date >= date_sub(current_date(), interval 14 day)
  {% endif %}
)

select
  date,
  country,
  platform,

  sum(dau)                                                     as dau,
  sum(new_users)                                               as new_users,
  max(wau)                                                     as wau,
  max(mau)                                                     as mau,
  sum(payers)                                                  as payers,
  sum(total_revenue)                                           as total_revenue,
  sum(iap_revenue)                                             as iap_revenue,
  sum(total_transactions)                                      as total_transactions,
  sum(sessions)                                                as sessions,

  safe_divide(sum(total_revenue), nullif(sum(dau), 0))         as arpdau,
  safe_divide(sum(iap_revenue), nullif(sum(payers), 0))        as arppu,
  safe_divide(sum(iap_revenue), nullif(sum(total_transactions), 0)) as revenue_per_transaction,

  -- DAU-weighted averages so retention/session rates aggregate sensibly.
  safe_divide(sum(d1_retention * dau), nullif(sum(dau), 0))    as d1_retention,
  safe_divide(sum(d7_retention * dau), nullif(sum(dau), 0))    as d7_retention,
  safe_divide(sum(d30_retention * dau), nullif(sum(dau), 0))   as d30_retention,
  safe_divide(sum(sessions_per_user * dau), nullif(sum(dau), 0))   as sessions_per_user,
  safe_divide(sum(avg_session_length * dau), nullif(sum(dau), 0))  as avg_session_length,
  safe_divide(sum(play_time_per_user * dau), nullif(sum(dau), 0))  as play_time_per_user

from src
group by 1, 2, 3

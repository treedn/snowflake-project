{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'date', 'data_type': 'date'},
    cluster_by=['app', 'network', 'country'],
    on_schema_change='append_new_columns'
) }}

-- UA performance from Adjust (single source of truth: Adjust ingests Meta cost natively
-- and is the only table that joins paid spend to attributed installs/revenue/ROAS).
-- Incremental: rebuild last 14 days each run (Adjust mutates retroactively as late
-- attributions arrive). Run `dbt run --full-refresh` if you need to fix older history.
select
  date,
  app,
  platform,
  country,
  channel                                                     as network,
  campaign,
  campaign_id,

  sum(impressions)                                            as impressions,
  sum(clicks)                                                 as clicks,
  sum(installs)                                               as installs,
  sum(paid_installs)                                          as paid_installs,
  sum(organic_installs)                                       as organic_installs,
  sum(reattributions)                                         as reattributions,
  sum(reinstalls)                                             as reinstalls,
  sum(uninstalls)                                             as uninstalls,
  sum(daus)                                                   as daus,
  sum(sessions)                                               as sessions,
  sum(events)                                                 as events,
  sum(revenue_events)                                         as revenue_events,

  sum(cost)                                                   as spend,
  sum(revenue)                                                as revenue,
  sum(cohort_revenue)                                         as cohort_revenue,
  sum(ad_revenue)                                             as ad_revenue,
  sum(all_revenue)                                            as all_revenue,
  sum(gross_profit)                                           as gross_profit,

  safe_divide(sum(clicks), nullif(sum(impressions), 0))       as ctr,
  safe_divide(sum(installs), nullif(sum(clicks), 0))          as cvr,
  safe_divide(sum(cost), nullif(sum(impressions), 0)) * 1000  as ecpm,
  safe_divide(sum(cost), nullif(sum(clicks), 0))              as ecpc,
  safe_divide(sum(cost), nullif(sum(installs), 0))            as ecpi,
  safe_divide(sum(revenue), nullif(sum(daus), 0))             as arpdau,
  safe_divide(sum(ad_revenue), nullif(sum(daus), 0))          as arpdau_ad,
  safe_divide(sum(all_revenue), nullif(sum(daus), 0))         as arpdau_all,
  safe_divide(sum(revenue), nullif(sum(all_revenue), 0))      as iap_share,
  safe_divide(sum(ad_revenue), nullif(sum(all_revenue), 0))   as ad_share,
  safe_divide(sum(cohort_revenue), nullif(sum(cost), 0))      as roas,
  safe_divide(sum(ad_revenue), nullif(sum(cost), 0))          as roas_ad,
  safe_divide(sum(all_revenue) - sum(cost), nullif(sum(cost), 0)) as roi

from {{ ref('stg_adjust__report') }}
{% if is_incremental() %}
where date >= date_sub(current_date(), interval 14 day)
{% endif %}
group by 1, 2, 3, 4, 5, 6, 7

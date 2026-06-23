{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'date', 'data_type': 'date'},
    cluster_by=['app', 'network', 'country'],
    on_schema_change='append_new_columns'
) }}

-- UA acquisition funnel from Adjust:
-- impressions → clicks → installs → revenue events → first purchases (revenue > 0).
-- (In-game level/progression funnels need player-event data; not in this mart.)
-- Incremental: rebuild last 14 days each run.
with base as (
  select
    date,
    app,
    platform,
    country,
    network,
    campaign,
    sum(impressions)                       as impressions,
    sum(clicks)                            as clicks,
    sum(installs)                          as installs,
    sum(events)                            as events,
    sum(revenue_events)                    as revenue_events,
    sum(cost)                              as spend,
    sum(revenue)                           as revenue,
    sum(cohort_revenue)                    as cohort_revenue
  from {{ ref('stg_adjust__report') }}
  {% if is_incremental() %}
  where date >= date_sub(current_date(), interval 14 day)
  {% endif %}
  group by 1, 2, 3, 4, 5, 6
)

select
  *,
  safe_divide(clicks, nullif(impressions, 0))         as impr_to_click_rate,
  safe_divide(installs, nullif(clicks, 0))            as click_to_install_rate,
  safe_divide(events, nullif(installs, 0))            as install_to_event_rate,
  safe_divide(revenue_events, nullif(installs, 0))    as install_to_purchase_rate,
  safe_divide(spend, nullif(installs, 0))             as cpi,
  safe_divide(cohort_revenue, nullif(installs, 0))    as install_arpu_d0
from base

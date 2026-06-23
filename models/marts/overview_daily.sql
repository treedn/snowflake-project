{{ config(materialized='view') }}

-- Single dashboard-friendly view: UA performance + engagement on
-- (date, app, platform, country). Both sides are first rolled up to that grain
-- so the join is one-to-one. Engagement does not carry network/campaign;
-- query ua_performance_daily directly when those splits are needed.
with ua as (
  select
    date,
    app,
    platform,
    country,
    sum(installs)                                                       as installs,
    sum(paid_installs)                                                  as paid_installs,
    sum(organic_installs)                                               as organic_installs,
    sum(spend)                                                          as spend,
    sum(revenue)                                                        as revenue,
    sum(cohort_revenue)                                                 as cohort_revenue,
    sum(ad_revenue)                                                     as ad_revenue,
    sum(impressions)                                                    as impressions,
    sum(clicks)                                                         as clicks,
    safe_divide(sum(spend), nullif(sum(installs), 0))                   as ecpi,
    safe_divide(sum(cohort_revenue), nullif(sum(spend), 0))             as roas
  from {{ ref('ua_performance_daily') }}
  group by 1, 2, 3, 4
),

eng as (
  select
    date,
    platform,
    country,
    sum(dau)                                                            as dau,
    sum(new_users)                                                      as new_users,
    sum(payers)                                                         as payers,
    sum(total_revenue)                                                  as engagement_total_revenue,
    sum(iap_revenue)                                                    as engagement_iap_revenue,
    sum(sessions)                                                       as sessions,
    safe_divide(sum(total_revenue), nullif(sum(dau), 0))                as arpdau,
    safe_divide(sum(iap_revenue), nullif(sum(payers), 0))               as arppu,
    safe_divide(sum(d1_retention * dau), nullif(sum(dau), 0))           as d1_retention,
    safe_divide(sum(d7_retention * dau), nullif(sum(dau), 0))           as d7_retention,
    safe_divide(sum(d30_retention * dau), nullif(sum(dau), 0))          as d30_retention
  from {{ ref('engagement_daily') }}
  group by 1, 2, 3
)

select
  coalesce(ua.date, eng.date)             as date,
  ua.app,
  coalesce(ua.platform, eng.platform)     as platform,
  coalesce(ua.country, eng.country)       as country,

  -- UA performance
  ua.installs,
  ua.paid_installs,
  ua.organic_installs,
  ua.impressions,
  ua.clicks,
  ua.spend,
  ua.revenue                              as adjust_revenue,
  ua.cohort_revenue,
  ua.ad_revenue                           as adjust_ad_revenue,
  ua.ecpi,
  ua.roas,

  -- Engagement
  eng.dau,
  eng.new_users,
  eng.payers,
  eng.sessions,
  eng.engagement_total_revenue,
  eng.engagement_iap_revenue,
  eng.arpdau,
  eng.arppu,
  eng.d1_retention,
  eng.d7_retention,
  eng.d30_retention

from ua
full outer join eng
  on ua.date     = eng.date
 and ua.platform = eng.platform
 and ua.country  = eng.country

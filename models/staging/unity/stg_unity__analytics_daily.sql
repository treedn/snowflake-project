{{ config(materialized='view') }}

select
  day                                  as date,
  upper(coalesce(country, ''))         as country,
  case lower(coalesce(platform, ''))
    when 'mac_client' then 'mac'
    else lower(coalesce(platform, ''))
  end                                  as platform,
  clientVersion                        as client_version,
  acquisitionChannel                   as acquisition_channel,

  uniqueUsers                          as dau,
  newUsers                             as new_users,
  WAU                                  as wau,
  MAU                                  as mau,
  newVsReturning                       as new_vs_returning,
  totalRevenue                         as total_revenue,
  iapRevenue                           as iap_revenue,
  ARPDAU                               as arpdau,
  ARPPU                                as arppu,
  payers,
  revenuePerTransaction                as revenue_per_transaction,
  totalTransactions                    as total_transactions,
  d1Retention                          as d1_retention,
  d7Retention                          as d7_retention,
  d30Retention                         as d30_retention,
  numberOfSessions                     as sessions,
  sessionsPerUser                      as sessions_per_user,
  averageSessionLength                 as avg_session_length,
  playTimePerUser                      as play_time_per_user

from {{ source('unity', 'unity_analytics_daily') }}

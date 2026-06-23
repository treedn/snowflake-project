with events as (
  select
    app_version,
    user_pseudo_id,
  	geo_country,
    event_date,
    ga_session_id,
    event_timestamp,
    level_id,
    event_name,
    product_id,
    price_dollars as event_value_in_usd
  from {{ ref('stg_events') }}
  where 1=1
  	and event_name in ('iap_purchase', 'level_started') 
  	and geo_country != 'Croatia'
)
,

iap_level as (
  select
    app_version,
    geo_country,
    user_pseudo_id,
    ga_session_id,
    event_timestamp,
    product_id,
    level_id,
    event_date,
    last_value(level_id ignore nulls) over (
          partition by user_pseudo_id -- If you need to backfill independently for different entities
          order by event_timestamp asc
          rows between unbounded preceding and current row
      ) as previous_level_id,
    first_VALUE(level_id IGNORE NULLS) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
  ) AS next_level_id,
    event_name,
    event_value_in_usd
  from events
  order by app_version, geo_country, user_pseudo_id, event_date
)

select
  app_version,
  geo_country,
  product_id,
  event_date,
  coalesce(previous_level_id,next_level_id) as level_id,
  sum(event_value_in_usd) as level_ltv
from iap_level
where ga_session_id in (select ga_session_id from events where event_value_in_usd > 0)
group by all
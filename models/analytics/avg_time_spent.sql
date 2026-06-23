with level_data as (
  select
    user_pseudo_id,
    app_version,
    event_date,
    geo_country,
    level_id,
    event_name,
    event_timestamp,
  from {{ ref('stg_events') }}
  where 1=1
  	and event_name in ('level_started','level_completed','level_failed')
  	and geo_country != 'Croatia'
)  
,

durations as (
  select
    user_pseudo_id,
    app_version,
  	geo_country,
    level_id,
    event_name,
    event_date,
    -- unquote two lines below to check for data accuracy
    -- event_timestamp,
    -- lag(event_timestamp) over (partition by user_pseudo_id order by event_timestamp) as previous_event_timestamp,
    timestamp_diff(event_timestamp,lag(event_timestamp) over (partition by user_pseudo_id order by event_timestamp),minute) as playtime
  from level_data
)

select 
  app_version,
  geo_country,
  level_id,
  user_pseudo_id,
  event_date,
  sum(playtime) as total_playtime
from durations
where 1=1
  and event_name in ('level_completed','level_failed')
group by all
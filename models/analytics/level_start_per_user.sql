with level_data as (
  select
    user_pseudo_id,
    app_version,
  	geo_country,
    event_date,
    level_id,
  from {{ ref('stg_events') }}
  where 1=1
  	and event_name in ('level_started') 
  	and geo_country != 'Croatia'
)  
,

level_starts as (
  select
    app_version,
    level_id,
    user_pseudo_id,
  	geo_country,
  	event_date,
    count(level_id) as level_starts_count
  from level_data
  group by all
)

select 
  app_version,
  geo_country,
  level_id,
  user_pseudo_id,
  event_date,
  level_starts_count
from level_starts
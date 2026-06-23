with starts as (
  select
    app_version,
    geo_country,
    user_pseudo_id,
    event_date,
    level_id,
    count(1) as tries_count,
  from {{ ref('stg_events') }}
  where 1=1
  	and event_name in ('level_started')
  	and geo_country != 'Croatia'
  group by all
)

select
  app_version,
  geo_country,
  level_id,
  tries_count,
  event_date,
  count(distinct user_pseudo_id) as users_count
from starts
group by all
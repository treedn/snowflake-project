with results as (
  select
    app_version,
    level_id,
    geo_country,
	  event_date,
    count(distinct user_pseudo_id) as users_count,
  from {{ ref('stg_events') }}
  where 1=1
    and event_name in ('level_completed') 
    and geo_country != 'Croatia'
    and app_version is not null
  group by all
) 

select *
from results
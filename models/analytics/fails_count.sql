with fails as (
  select
    app_version,
    geo_country,
	event_date,
    user_pseudo_id,
    level_id,
    count(1) as fails_count,
  from {{ ref('stg_events') }}
  where 1=1
  	and event_name in ('level_failed')
  	and geo_country != 'Croatia'
  group by all
)

select
  app_version,
  geo_country,
  level_id,
  fails_count,
  event_date,
  count(distinct user_pseudo_id) as users_count
from fails
group by all
order by app_version, geo_country, level_id, event_date
select
  app_version,
  geo_country,
  event_date,
  level_id,
  count(distinct case when event_name in ('level_started') then user_pseudo_id end) as user_started,
  count(distinct case when event_name in ('level_failed') then user_pseudo_id end) as user_failed,
from {{ ref('stg_events') }}
where 1=1
	and event_name in ('level_started','level_completed','level_failed')
  	and geo_country != 'Croatia'
group by all
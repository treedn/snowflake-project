select
    app_version,
	  geo_country,
    event_date,
    level_id,
    reason as fail_reason,
    count(distinct user_pseudo_id) as users_count,
  from {{ ref('stg_events') }}
  where 1=1
	and event_name in ('level_failed')
  	and geo_country != 'Croatia'
  group by all
with first_date as (
  select
    user_id,
    min(event_date) as first_active_date
  FROM `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
  group by user_id
)
,

events as (
  select
    events.user_id,
    (select value.int_value from unnest(event_params) where key = 'level_id') as level_id,
    date_diff(parse_date('%Y%m%d', event_date), parse_date('%Y%m%d', first_active_date), day) as active_day,
  FROM `chef-master-8f916.analytics_448269098.events_*` events
  join first_date on events.user_id = first_date.user_id
  where 1=1
    and event_name not in ('user_engagement', 'screen_change')
    and app_info.version = '0.5.1'
)
,

max_level_day as (
  select
    user_id,
    active_day,
    max(level_id) as day_level
  from events
  where active_day <= 4
  group by 1,2
)

select
  active_day,
  day_level,
  count(user_id) as user_count
from max_level_day
group by 1,2
order by 1

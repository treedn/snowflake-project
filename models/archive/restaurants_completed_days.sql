with qualified_users as (
  select 
    user_id,
    case
        when app_info.version = '0.1.10' then '0.1.9(10)'
        else app_info.version
      end as version,
    (select value.int_value from unnest(event_params) where key = 'level_id') as level_id,
    min(event_date) as completed_level_date,
  from `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and event_name in ('level_completed')
    and (select value.int_value from unnest(event_params) where key = 'level_id') in (60041,60151) 
  group by all
) 
,

user_first as (
  select
    user_id,
    min(event_date) as first_date
  from `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and event_name in ('level_completed')
    and user_id in (select user_id from qualified_users)
  group by user_id
)

select
  version,
  qualified_users.user_id,
  qualified_users.level_id,
  date_diff(parse_date('%Y%m%d',completed_level_date), parse_date('%Y%m%d',first_date), day) as complete_duration
from qualified_users
join user_first on qualified_users.user_id = user_first.user_id
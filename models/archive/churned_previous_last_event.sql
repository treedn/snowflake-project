with version_launch as (
  select
    case
      when app_info.version = '0.1.10' then '0.1.9.1'
      else app_info.version
    end as version,
    min(parse_date('%Y%m%d', event_date)) as launch_date
  FROM `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and geo.country not in ('Croatia')
  group by 1
)
,

users as (
  select
    user_id,
    min(parse_date('%Y%m%d', event_date)) as first_date,
    max(parse_date('%Y%m%d', event_date)) as last_date,
    max(event_timestamp) as last_event_timestamp
  FROM `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and event_name not in ('user_engagement', 'screen_change')
  group by all
)
,

churned_users as (
  select
    users.*,
    min(version_launch.version) as version,
  from users
  join version_launch on users.first_date <= version_launch.launch_date
  where 1=1
    and (
      users.first_date = users.last_date
      or users.first_date = users.last_date - 1
    )
  group by all
)
,

events as (
  select
    user_id,
    event_timestamp,
    event_name,
    lag(event_name) over (partition by user_id order by event_timestamp asc) as previous_event_name,
  FROM `chef-master-8f916.analytics_448269098.events_*` events
  where 1=1
    and event_name not in ('user_engagement', 'screen_change')
    and user_id in (select user_id from churned_users)
)

select
  case
    when churned_users.version = '0.1.9.1' then '0.1.10'
    else churned_users.version
  end as version,
  events.user_id,
  events.event_name,
  events.previous_event_name,
  churned_users.first_date,
  churned_users.last_date,
from events
join churned_users on (events.user_id = churned_users.user_id and events.event_timestamp = churned_users.last_event_timestamp)

with active_dates as (
    select
      geo.country,
      user_id,
      case
        when app_info.version = '0.1.10' then '0.1.9(10)'
        else app_info.version
      end as version,
      event_date,
      DENSE_RANK() OVER (PARTITION BY user_id ORDER BY event_date) - 1 as active_day,
    FROM `chef-master-8f916.analytics_448269098.events_*` events
)
,

days_active as (
  select 
    * except (version,active_day),
    case
      when active_day >= 30 then 'f)30+'
      when active_day >= 14 then 'e)14-30'
      when active_day >= 7 then 'd)7-14'
      when active_day >= 2 then 'c)2-6'
  	  when active_day = 1 then 'b)1'
      else 'a)0'
    end as active_status,
    min(version) as version,
  from active_dates
  group by all
  order by version desc
)
,

active_statuses as (
  select 
    user_id,
    version,
    country,
    max(active_status) as active_status
  from days_active
  group by all
)
,

results as (
  select
    version,
    active_status,
    count(distinct user_id) as users_count
  from active_statuses
  group by rollup (version, active_status)
)

select 
  active_statuses.version,
  active_statuses.active_status,
  active_statuses.users_count,
  version.users_count as version_total_users,
  safe_divide(active_statuses.users_count,version.users_count) as version_retention
from results active_statuses
join results version on active_statuses.version = version.version
where 1=1
  and version.active_status is null
  and active_statuses.active_status is not null

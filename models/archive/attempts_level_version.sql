with level_attempts as (
  select
    case
        when app_info.version = '0.1.10' then '0.1.9(10)'
        else app_info.version
      end as version,
    (select value.int_value from unnest(event_params) where key = 'level_id') as level_id,
    count(1) as attempts,
  from `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and event_name in ('level_started')
    and (select value.int_value from unnest(event_params) where key = 'level_id') is not null
  group by rollup (version, level_id)
)

select 
  levels.version,
  levels.level_id,
  levels.attempts,
  levels.attempts/versions.attempts as version_retention
from level_attempts versions
join level_attempts levels on levels.version = versions.version
where 1=1
  and versions.level_id is null
  and levels.level_id is not null
order by 1 desc, 2 asc

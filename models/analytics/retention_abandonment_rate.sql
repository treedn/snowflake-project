with new_users as (
  select
    app_version,
    user_pseudo_id
  FROM `chef-master-8f916`.`staging`.`stg_events`
  where 1=1
    and user_pseudo_id is not null
    and event_name in (
    'new_player'
    )
)
,

level_retention as (
select  
  new_users.app_version,
  events.level_id,  
  count(distinct events.user_pseudo_id) as user_count
from {{ ref('stg_events') }} events
join new_users on events.user_pseudo_id = new_users.user_pseudo_id
group by all
),

results as (
select
  level.app_version,
  level.level_id,
  level.user_count,
  pool.user_count as pool_count,
  safe_divide(level.user_count,pool.user_count) as remain_rate,
  safe_divide((lag(level.user_count) over (partition by level.app_version order by level.level_id asc) - level.user_count),lag(level.user_count) over (partition by level.app_version order by level.level_id asc)) as abandonment_rate
from level_retention level
join level_retention pool on level.app_version = pool.app_version
where 1=1
  and pool.level_id = 60000
)

select * 
from results
order by 1 desc
with new_users as (
  select
    app_version,
    user_pseudo_id,
  from {{ ref('stg_events') }}
  where user_pseudo_id is not null
    and event_name = 'new_player'
),

level_completions as (
  select
    nu.app_version,
    e.event_date as cohort_date,
    e.level_id,
    count(distinct e.user_pseudo_id) as users_completed
  from {{ ref('stg_events') }} e
  join new_users nu on e.user_pseudo_id = nu.user_pseudo_id
  where e.event_name = 'level_completed'
  group by all
),

pool as (
  select
    app_version,
    cohort_date,
    users_completed as pool_count
  from level_completions
  where level_id = 60000
),

with_lag as (
  select
    lc.app_version,
    lc.cohort_date,
    lc.level_id,
    lc.users_completed,
    lag(lc.users_completed) over (
      partition by lc.app_version, lc.cohort_date 
      order by lc.level_id asc
    ) as prev_level_users
  from level_completions lc
)

select
  wl.app_version,
  wl.cohort_date,
  wl.level_id,
  wl.users_completed,
  coalesce(p.pool_count, 0) as pool_count,
  coalesce(wl.prev_level_users, 0) as prev_level_users,
  -- abandoned at this level
  greatest(coalesce(wl.prev_level_users, 0) - wl.users_completed, 0) as users_abandoned
from with_lag wl
left join pool p
  on wl.app_version = p.app_version
  and wl.cohort_date = p.cohort_date
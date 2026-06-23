with new_users as (
  select
    app_version,
    user_pseudo_id
  FROM {{ ref('stg_events') }}
  where 1=1
    and user_pseudo_id is not null
    and event_name in (
    'new_player'
    )
)
,

balance_data as (
  SELECT 
    new_users.app_version,
    geo_country,
    new_users.user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    ga_session_number,
    ga_session_id,
    -- level_started params
    level_id,
    -- currency_earned and currency_spent params
    currency_type,
    reason,
    amount
  FROM {{ ref('stg_events') }} events
  join new_users on (
      events.user_pseudo_id = new_users.user_pseudo_id and events.app_version = new_users.app_version
  )
  where 1=1
    and event_name in (
      'currency_earned',
      'currency_spent',
      'level_started'
      )
    and geo_country != 'Croatia'
)
,

level_attribution as (
  select
    *,
    last_value(level_id ignore nulls) over (
        partition by user_pseudo_id -- If you need to backfill independently for different entities
        order by event_timestamp asc
        rows between unbounded preceding and current row
    ) as previous_level_id,
    first_VALUE(level_id IGNORE NULLS) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
    ) AS next_level_id,
  from balance_data
)
,

gameplay_log as (
  select 
    * except (level_id, previous_level_id, next_level_id, currency_type),
    coalesce(previous_level_id, level_id, next_level_id) as level_id
  from level_attribution
  where 1=1
    and currency_type = 'Coins'
    and event_name in (
      'currency_earned',
      'currency_spent'
      )
  order by user_pseudo_id, event_timestamp
)
,

level_earned_spent as (
  select
    app_version,
    level_id,
    event_name,
    user_pseudo_id,
    event_date,
    sum(amount) as total_amount
  from gameplay_log
  where 1=1
    and level_id is not null
  group by all
)
,

level_balance as (
  select
    app_version,
    level_id,
    user_pseudo_id,
    event_date,
  sum(case when event_name = 'currency_earned' then total_amount end) as earned_amount,
  sum(case when event_name = 'currency_spent' then total_amount end) as spent_amount,
  coalesce(sum(case when event_name = 'currency_earned' then total_amount end),0) - coalesce(sum(case when event_name = 'currency_spent' then total_amount end),0) as sub_total_amount
  from level_earned_spent
  group by all
  order by app_version, user_pseudo_id, level_id
)
,

cumulative_balance as (
  SELECT
      app_version,
      level_id,
      user_pseudo_id,
      event_date,
      sub_total_amount,
      SUM(sub_total_amount) OVER (partition by user_pseudo_id ORDER BY app_version, level_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sum
  FROM level_balance
)

select
*
from cumulative_balance
where 1=1
  and cumulative_sum > 0
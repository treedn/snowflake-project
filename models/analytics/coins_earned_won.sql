with balance_data as (
  SELECT 
    app_version,
    geo_country,
    user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    ga_session_number,
    ga_session_id,
    level_id,
    currency_type,
    reason,
    amount
  FROM {{ ref('stg_events') }}
  where 1=1
    and user_pseudo_id is not null
    and event_name in (
      'currency_earned',
      'level_started'
      )
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
      'currency_earned'
      )
    and reason = 'ChallengeWon'
  order by user_pseudo_id, event_timestamp
)
,

earned_events as (
  select
    app_version,
    level_id,
    event_name,
    user_pseudo_id,
    geo_country,
  	event_date,
    amount as total_amount,
    DENSE_RANK() OVER (partition by app_version, user_pseudo_id, level_id ORDER BY event_timestamp) AS level_index
  from gameplay_log
  order by app_version, level_id, event_name, user_pseudo_id
)

select
  * except (level_index)
from earned_events
where 1=1
and level_index = 1

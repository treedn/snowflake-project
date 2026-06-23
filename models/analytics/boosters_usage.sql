with iap_players as (
  select distinct
    user_pseudo_id
  FROM {{ ref('stg_events') }}
  where 1=1
    and price_dollars > 0
    and event_name = 'iap_purchase'
)
,

booster_data as (
  SELECT 
    app_version,
    geo_country,
    user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    case when user_pseudo_id in (select * from iap_players) then 1 else 0 end as iap_players,
    level_id,
    booster_id,
  FROM {{ ref('stg_events') }} events
  where 1=1
    and user_pseudo_id is not null
    and event_name in (
      'booster_used',
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
  from booster_data
)
,

gameplay_log as (
  select 
    * except (level_id, previous_level_id, next_level_id, object_id),
    coalesce(previous_level_id, level_id, next_level_id) as level_id
  from level_attribution
  join `dbt_tri.game_objects` objects on level_attribution.booster_id = objects.object_id 
  where 1=1
    and event_name in (
      'booster_used'
      )
  order by user_pseudo_id, event_timestamp
)

select *
from gameplay_log
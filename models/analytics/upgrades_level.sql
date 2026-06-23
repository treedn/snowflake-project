with upgrades as (
  SELECT 
    app_version,
    geo_country,
    user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    level_id,
    coalesce (staff_id, object_id) as item_id,
    coalesce (staff_level, object_level) as upgrade_level,
  FROM {{ ref('stg_events') }} events
  where 1=1
      and event_name in ('level_started','staff_level_purchase','object_level_purchase')
      and user_pseudo_id is not null
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
  from upgrades
)
,

gameplay_log as (
  select 
    * except (level_id, previous_level_id, next_level_id, upgrade_level),
    object_name as item_name,
    upgrade_level,
    coalesce(previous_level_id, level_id, next_level_id) as level_id
  from level_attribution
  left join {{ source('dbt_tri', 'game_objects') }} objects on (level_attribution.item_id = objects.object_id)
  where 1=1
    and event_name in (
      'staff_level_purchase',
      'object_level_purchase'
      )
    -- and object_name is null
  order by user_pseudo_id, event_timestamp
)

select 
  *
from gameplay_log
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
    -- currency_earned and currency_spent params
    currency_type,
    reason,
    amount,
    -- iap_purchase params  
    item_name,
    price_dollars,
    price_gems,
    -- objects and staffs purchase params
    object_level,
    staff_level,
    object_id,
    staff_id
  FROM {{ ref('stg_events') }}
  where 1=1
    and user_pseudo_id is not null
    and event_name in (
      'currency_earned',
      'currency_spent',
      'level_started',
      'iap_purchase',
      'object_level_purchase', 
      'staff_level_purchase'
      )
)
,

level_attribution as (
  select
    * except (price_dollars, price_gems, object_level, staff_level, object_id, staff_id),
    coalesce(price_dollars, price_gems) as iap_value,
    coalesce(object_level, staff_level) as upgrade_level,
    coalesce(object_id, staff_id) as upgrade_id,
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
    * except (level_id, previous_level_id, next_level_id, upgrade_id, object_id, object_name),
    game_objects.object_name as upgrade_name,
    coalesce(previous_level_id, level_id, next_level_id) as attributed_level
  from level_attribution
  left join {{ source('dbt_tri', 'game_objects') }} game_objects on level_attribution.upgrade_id = game_objects.object_id
  where 1=1
    -- and event_name in ('currency_earned','currency_spent', 'iap_purchase')
  order by app_version, geo_country, attributed_level, user_pseudo_id, event_timestamp
)

select 
  app_version,
  geo_country,
  user_pseudo_id,
  event_date,
  event_timestamp,
  event_name,
  attributed_level,
  upgrade_name,
  upgrade_level,
  iap_value,
  reason,
  amount,
  item_name,
from gameplay_log
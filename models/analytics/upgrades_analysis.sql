with fail_data as (
    SELECT
        app_version,
        user_pseudo_id,
        level_id,
        max(event_timestamp) as event_timestamp,
    FROM {{ ref('stg_events') }}
    where 1=1
        and app_version >= '0.1.8'
        and event_name = 'level_failed'
    group by all
)
,

upgrades as (
    SELECT 
        fail_data.app_version,
        fail_data.user_pseudo_id,
        fail_data.level_id,
        fail_data.event_timestamp,
        coalesce (staff_id, object_id) as item_id,
        coalesce (staff_level, object_level) as upgrade_level,
    FROM {{ ref('stg_events') }} events
    join fail_data on (
        events.user_pseudo_id = fail_data.user_pseudo_id 
        and events.event_timestamp <= fail_data.event_timestamp
    )
    where 1=1
        and events.app_version >= '0.1.8'
        and event_name in ('staff_level_purchase','object_level_purchase')
)
,

upgrades_at_fail as (
    select
        app_version,
        user_pseudo_id,
        level_id,
        event_timestamp, 
        item_id,
        max(upgrade_level) as upgrade_level,
    from upgrades
    group by 1,2,3,4,5
)
,

all_upgrades_by_level as (
  SELECT distinct
    upgrades_recommendation.level_id as upgrade_level_id,
    previous_upgrade.*
  FROM {{ source('dbt_tri', 'level_upgrade_recommendations') }} upgrades_recommendation
  join {{ source('dbt_tri', 'level_upgrade_recommendations') }} previous_upgrade on (
    upgrades_recommendation.level_id >= previous_upgrade.level_id
  )
)
,

max_upgrades_by_level as (
  select
    upgrade_level_id,
    item_id,
    max(upgrade_level) as upgrade_level,
  from all_upgrades_by_level
  group by 1,2
)
,

results as (
    select 
        upgrades_at_fail.app_version,
        upgrades_at_fail.user_pseudo_id,
        upgrades_at_fail.level_id,
        upgrades_at_fail.item_id,
        upgrades_at_fail.upgrade_level,
        -- recommended
        max_upgrades_by_level.upgrade_level_id as recommended_level_id,
        max_upgrades_by_level.item_id as recommended_item_id,
        max_upgrades_by_level.upgrade_level as recommended_upgrade_level,
        case
            when upgrades_at_fail.upgrade_level >= max_upgrades_by_level.upgrade_level then 'pass'
            else 'fail'
        end as follow_recommendation,
    from upgrades_at_fail
    join max_upgrades_by_level on ( 
        upgrades_at_fail.level_id = max_upgrades_by_level.upgrade_level_id
        and upgrades_at_fail.item_id = max_upgrades_by_level.item_id
    )
    order by app_version, user_pseudo_id, level_id, item_id
)

select
    *
from results
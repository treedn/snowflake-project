WITH players_event AS (
  SELECT
    app_version,
    geo_country,
    user_pseudo_id,
    event_date,
    level_id,
    DENSE_RANK()
      OVER (PARTITION BY user_pseudo_id ORDER BY event_date) - 1
      AS active_day
  FROM
    {{ ref('stg_events') }} AS events
  WHERE
    1 = 1 AND event_name NOT IN ('user_engagement', 'screen_change')
)
,

active_day_max_level as (
  SELECT
    app_version,
    geo_country,
    user_pseudo_id,
    event_date,
    max(level_id) as max_level_day,
    active_day,
  FROM
    players_event
  WHERE 1 = 1
    and geo_country != 'Croatia'
    and user_pseudo_id is not null
    and level_id is not null
  group by all
  order by app_version, geo_country, user_pseudo_id, active_day
)

select *
from active_day_max_level

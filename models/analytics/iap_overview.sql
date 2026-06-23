with iap_players as (
  select distinct
    user_pseudo_id,
    event_timestamp,
    DENSE_RANK() OVER (partition by user_pseudo_id ORDER BY event_timestamp) AS iap_index
  FROM {{ ref('stg_events') }}
  where 1=1
    and price_dollars > 0
    and event_name = 'iap_purchase'
)
,

players_event as (
  select
    events.app_version,
    iap_players.user_pseudo_id,
    events.event_date,
    events.event_timestamp,
    product_id,
    price_dollars,
    case when events.event_timestamp = iap_players.event_timestamp then 1 else 0 end as is_purchase, 
    iap_players.iap_index,
    DENSE_RANK() OVER (partition by events.user_pseudo_id ORDER BY events.event_date) AS active_day,
  FROM {{ ref('stg_events') }} events
  left join iap_players on events.user_pseudo_id = iap_players.user_pseudo_id and events.event_timestamp = iap_players.event_timestamp
  where 1=1
    and event_name not in ('user_engagement', 'screen_change')
)

select
  *
from players_event
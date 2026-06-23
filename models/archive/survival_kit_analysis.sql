with iap_users as (
  select distinct
    user_pseudo_id
  FROM {{ ref('stg_events') }}
  where 1=1
    and price_dollars > 0
    and event_name = 'iap_purchase'
    and item_name = 'Survival Kit'
) 
,

user_first_event as(
  select
    user_pseudo_id,
    min(event_date) as user_first_date
  FROM {{ ref('stg_events') }}
  where 1=1
    and user_pseudo_id in ( select user_pseudo_id from iap_users)
  group by 1
)
,

events as (
  select
    events_fb.user_pseudo_id,
    ROW_NUMBER() OVER (PARTITION BY events_fb.user_pseudo_id ORDER BY event_timestamp) as event_order,
    date_diff(event_date,user_first_date, day) as days_since_first_event,
    event_name,
    event_params,
    event_timestamp,
    event_date,
    ga_session_id,
    device.mobile_model_name as mobile_model_name,
    geo.region as region,
  FROM {{ ref('stg_events') }} events_fb
  join user_first_event on events_fb.user_pseudo_id = user_first_event.user_pseudo_id
  where 1=1
    and event_name not in ('user_engagement')
)
,

iap_events as (
  select 
    user_pseudo_id,
    event_order
  from events
  where 1=1
    and event_name = 'iap_purchase'
    and (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name') in (
      'Survival Kit'
    )
)
,

after_events as (
  select
    events.*
  from events
  join iap_events on (
    events.user_pseudo_id = iap_events.user_pseudo_id and
    events.event_order between iap_events.event_order - 10 and iap_events.event_order 
  )
)

select 
*
from after_events

with purchase_users as (
  select distinct
    user_id,
    event_timestamp,
  FROM `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'price_dollars') > 0
    and event_name = 'iap_purchase'
)
,

first_date as (
  select
    user_id,
    min(event_date) as first_active_date
  FROM `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and user_id in (SELECT user_id FROM purchase_users)
  group by user_id
)
,

events as (
  select
    app_info.version,
    events.user_id,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name') AS product_name,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'price_dollars') as price_dollars,
    lag(event_name) over (partition by events.user_id order by event_timestamp asc) as previous_event_name,
    parse_date('%Y%m%d', event_date) as event_date,
    parse_date('%Y%m%d', first_active_date) as first_active_date,
    date_diff(parse_date('%Y%m%d', event_date), parse_date('%Y%m%d', first_active_date), day) as active_day,
  FROM `chef-master-8f916.analytics_448269098.events_*` events
  join first_date on events.user_id = first_date.user_id
  where 1=1
    and event_name not in ('user_engagement', 'screen_change')
)

select
  events.* except (event_timestamp)
from events
join purchase_users on (events.user_id = purchase_users.user_id and events.event_timestamp = purchase_users.event_timestamp)

with iap_users as (
    SELECT 
        user_id,
        event_timestamp
    FROM `chef-master-8f916.analytics_448269098.events_*`
    where 1=1
        and user_first_touch_timestamp >= 1760918400000000
        and event_name = 'iap_purchase'
        and (SELECT value.double_value FROM UNNEST(event_params) WHERE key = "price_dollars") > 0
)
,

user_events as (
    select
        *,
        lag(event_name) over (
            partition by user_id 
            order by event_timestamp asc
        ) as previous_event_name,
        lag(event_params) over (
            partition by user_id 
            order by event_timestamp asc
        ) as previous_event_params,
        last_value(level_id ignore nulls) over (
            partition by user_id 
            order by event_timestamp asc
            rows between unbounded preceding and current row
        ) as attributed_level_id,
    from (   
        SELECT 
            events.user_id,
            events.event_timestamp,
            (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "level_id") as level_id,
            event_name,
            event_params,
        FROM `chef-master-8f916.analytics_448269098.events_*` events
        join iap_users on (events.user_id = iap_users.user_id and events.event_timestamp <= iap_users.event_timestamp)
        where 1=1
            and event_name not in ('currency_earned','in_app_purchase','user_engagement','screen_change','iap_purchase_failed')
    )
)

select
    user_id,
    attributed_level_id as level_id,
    timestamp_micros(event_timestamp) as event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "item_name") as item_name,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = "price_dollars") as price_dollars,
    previous_event_name,
from user_events
where 1=1
    and event_name = 'iap_purchase'
    and (SELECT value.double_value FROM UNNEST(event_params) WHERE key = "price_dollars") > 0
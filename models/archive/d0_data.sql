with churn_users as (
  SELECT distinct
    user_id
  FROM `chef-master-8f916.analytics_448269098.events_*`
  where 1=1
    and user_first_touch_timestamp >= 1760918400000000
    and PARSE_DATE('%Y%m%d', event_date) > date(timestamp_millis((SELECT value.int_value FROM UNNEST(user_properties) WHERE key = "first_open_time")))
    and user_id is not null
)
,

users_playtime as (
  SELECT
    user_id,
    sum(timestamp_diff(session_end_time, session_start_time, minute)) as engaged_duration,
    max(session_end_time) as session_end_time,
  from (
    SELECT
        user_id,
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "ga_session_id") as ga_session_number,
        timestamp_micros(min(event_timestamp)) as session_start_time,
        timestamp_micros(max(event_timestamp)) as session_end_time,
      FROM `chef-master-8f916.analytics_448269098.events_*`
      where 1=1
        and user_first_touch_timestamp >= 1760918400000000
    --     and user_id not in (select user_id from churn_users)
        and user_id is not null
        and parse_date('%Y%m%d',event_date) = date(timestamp_micros(user_first_touch_timestamp))
        and event_name not in ('user_engagement')
      group by 1,2
  )
  group by 1
)
,

user_activities as (
  select
    events.event_date,
    case
      when churn_users.user_id is null then 'churn'
      else 'active'
    end as d0_status,
    case
      when event_name = 'iap_purchase' then 'paid'
      else 'unpaid'
    end as paid_users,
    -- users_playtime.engaged_duration,
    timestamp_micros(events.event_timestamp) as event_timestamp,
    timestamp_micros(events.user_first_touch_timestamp) as user_first_touch_timestamp,
    traffic_source.source,
    events.user_id,
    events.event_name,
    -- events.event_params,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "ga_session_id") as ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "ga_session_number") as ga_session_number,
    -- tutorial_step
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "tutorial_id") as tutorial_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "step_num") as step_num,
    -- level_started, level_failed, level_completed
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "level_id") as level_id,
    -- booster_used
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "booster_id") as booster_id,
    -- currency_spent, currency_earned
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "reason") as reason,
    -- challenge_event
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "event_name") as challenge_event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "object_name") as object_name,
    -- screen_change
    -- (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "from_screen") as from_screen,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "to_screen") as to_screen,
    -- device.mobile_model_name,
    -- (SELECT value.double_value FROM UNNEST(event_params) WHERE key = "time_spent") as time_spent,
  FROM `chef-master-8f916.analytics_448269098.events_*` events
  left join churn_users on events.user_id = churn_users.user_id
  where 1=1
    and event_date >= '20251020'
    and parse_date('%Y%m%d',event_date) = date(timestamp_micros(events.user_first_touch_timestamp))
)
,

level_attribution as (
  select
    user_id,
    event_date,
    d0_status,
  	paid_users,
    user_activities.source,
    event_name,
    event_timestamp,
    user_first_touch_timestamp,
    boosters.name as booster_name,
    case
      when event_name in ('screen_change') then to_screen
      when event_name in ('challenge_event') then concat(challenge_event_name,'_',object_name)
      when event_name in ('tutorial_step') then concat(tutorial_id,'_',step_num)
      when event_name in ('tutorial_completed') then cast(tutorial_id as string)
      when event_name in ('level_started','level_completed') then cast(level_id as string)
    end as sub_event,
    last_value(level_id ignore nulls) over (
          partition by ga_session_id 
          order by event_timestamp asc
          rows between unbounded preceding and current row
      ) as level_id,
  from user_activities
  left join `chef-master-8f916.analytics_448269098.boosters` boosters on user_activities.booster_id = boosters.booster_id
)

select
  level_attribution.*,
  users_playtime.engaged_duration,
  users_playtime.session_end_time
from level_attribution
join users_playtime on (level_attribution.user_id = users_playtime.user_id and level_attribution.event_timestamp = users_playtime.session_end_time)
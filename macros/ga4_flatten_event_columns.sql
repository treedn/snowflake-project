{#
  GA4 / Firebase event flattener.

  stg_events_daily (finalized `events_*`) and stg_events_intraday
  (`events_intraday_*`) share an identical projection: the same top-level
  fields, the same flattened device/geo/app_info/traffic_source structs, and the
  same ~60 columns pivoted out of the `event_params` repeated record. Only their
  FROM/WHERE differ.

  Keeping that projection in one macro means the two shards can never silently
  drift apart (a drift here causes the UNION ALL in stg_events to fail dbt0301),
  and PII handling (user_id) is applied in exactly one place.

  `int_param(key)` / `dbl_param(key)` / `str_param(key)` are small helpers for
  the repeated `(SELECT value.<type>_value FROM UNNEST(event_params) ...)`
  pattern.
#}

{% macro _ga4_param(key, value_type) -%}
    (select value.{{ value_type }}_value from unnest(event_params) where key = '{{ key }}')
{%- endmacro %}

{% macro ga4_flatten_event_columns() %}
  parse_date('%Y%m%d', event_date)                                          as event_date,
  timestamp_micros(event_timestamp)                                         as event_timestamp,
  event_name,
  event_value_in_usd,
  user_pseudo_id,
  timestamp_micros(user_first_touch_timestamp)                             as user_first_touch_timestamp,

  device.category                                                           as device_category,
  device.mobile_brand_name                                                  as device_mobile_brand_name,
  device.mobile_model_name                                                  as device_mobile_model_name,
  device.mobile_marketing_name                                              as device_mobile_marketing_name,
  device.mobile_os_hardware_model                                           as device_mobile_os_hardware_model,
  device.operating_system                                                   as device_operating_system,
  device.operating_system_version                                           as device_operating_system_version,
  device.language                                                           as device_language,
  device.is_limited_ad_tracking                                             as device_is_limited_ad_tracking,
  device.time_zone_offset_seconds                                           as device_time_zone_offset_seconds,

  geo.continent                                                             as geo_continent,
  geo.country                                                               as geo_country,
  geo.region                                                                as geo_region,
  geo.city                                                                  as geo_city,
  geo.sub_continent                                                         as geo_sub_continent,
  geo.metro                                                                 as geo_metro,

  app_info.id                                                               as app_info_id,
  app_info.version                                                          as app_version,
  app_info.install_store                                                    as app_info_install_store,
  app_info.firebase_app_id                                                  as app_info_firebase_app_id,
  app_info.install_source                                                   as app_info_install_source,

  traffic_source.name                                                       as traffic_source_name,
  traffic_source.medium                                                     as traffic_source_medium,
  traffic_source.source                                                     as traffic_source_source,

  stream_id,
  platform,

  {{ _ga4_param('booster_id', 'int') }}           as booster_id,
  {{ _ga4_param('day_num', 'int') }}              as day_num,
  {{ _ga4_param('doubleReward', 'int') }}         as double_reward,
  {{ _ga4_param('engagement_time_msec', 'int') }} as engagement_time_msec,
  {{ _ga4_param('entrances', 'int') }}            as entrances,
  {{ _ga4_param('firebase_conversion', 'int') }}  as firebase_conversion,
  {{ _ga4_param('food_id', 'int') }}              as food_id,
  {{ _ga4_param('ga_session_id', 'int') }}        as ga_session_id,
  {{ _ga4_param('ga_session_number', 'int') }}    as ga_session_number,
  {{ _ga4_param('gem_cost', 'int') }}             as gem_cost,
  {{ _ga4_param('level_id', 'int') }}             as level_id,
  {{ _ga4_param('level_num', 'int') }}            as level_num,
  {{ _ga4_param('newAvatarId', 'int') }}          as new_avatar_id,
  {{ _ga4_param('object_id', 'int') }}            as object_id,
  {{ _ga4_param('object_level', 'int') }}         as object_level,
  {{ _ga4_param('price', 'int') }}                as price,
  {{ _ga4_param('price_gems', 'int') }}           as price_gems,
  {{ _ga4_param('quantity', 'int') }}             as quantity,
  {{ _ga4_param('quest_id', 'int') }}             as quest_id,
  {{ _ga4_param('refresh', 'int') }}              as refresh,
  {{ _ga4_param('reward_amount', 'int') }}        as reward_amount,
  {{ _ga4_param('staff_id', 'int') }}             as staff_id,
  {{ _ga4_param('staff_level', 'int') }}          as staff_level,
  {{ _ga4_param('step_num', 'int') }}             as step_num,
  {{ _ga4_param('time', 'int') }}                 as time,
  {{ _ga4_param('timestamp', 'int') }}            as param_timestamp,
  {{ _ga4_param('tutorial_id', 'int') }}          as tutorial_id,
  {{ _ga4_param('validated', 'int') }}            as validated,
  cast(coalesce(
    {{ _ga4_param('value', 'int') }},
    {{ _ga4_param('value', 'double') }}
  ) as float64)                                   as param_value,

  cast(coalesce(
    {{ _ga4_param('amount', 'double') }},
    {{ _ga4_param('amount', 'int') }}
  ) as float64)                                   as amount,
  {{ _ga4_param('price_dollars', 'double') }}     as price_dollars,
  {{ _ga4_param('time_spent', 'double') }}        as time_spent,

  {{ _ga4_param('ad', 'int') }}                       as ad,
  {{ _ga4_param('currency', 'string') }}             as currency,
  {{ _ga4_param('currency_type', 'string') }}        as currency_type,
  {{ _ga4_param('event_name', 'string') }}           as param_event_name,
  {{ _ga4_param('firebase_event_origin', 'string') }} as firebase_event_origin,
  {{ _ga4_param('from_screen', 'string') }}          as from_screen,
  {{ _ga4_param('item_name', 'string') }}            as item_name,
  {{ _ga4_param('location', 'string') }}             as location,
  {{ _ga4_param('newName', 'string') }}              as new_name,
  {{ _ga4_param('object_name', 'string') }}          as object_name,
  {{ _ga4_param('placement', 'string') }}            as placement,
  {{ _ga4_param('product_id', 'string') }}           as product_id,
  {{ _ga4_param('product_name', 'string') }}         as product_name,
  {{ _ga4_param('reason', 'string') }}               as reason,
  {{ _ga4_param('reward_type', 'string') }}          as reward_type,
  {{ _ga4_param('source', 'string') }}               as param_source,
  {{ _ga4_param('status', 'string') }}               as status,
  {{ _ga4_param('to_screen', 'string') }}            as to_screen,
  {{ _ga4_param('type', 'string') }}                 as type,
  {{ _ga4_param('with_ads', 'string') }}             as with_ads,

  -- PII: user_id is a stable cross-device account identifier. Pseudonymise it
  -- with a salted SHA-256 so no raw account id is ever persisted, while joins on
  -- the hash still work. See macros/mask_pii.sql + docs/data_governance.md.
  {{ hash_pii('user_id') }}                          as user_id
{% endmacro %}


{#
  The allow-list of game events we keep out of the raw GA4 firehose. Shared by
  the daily and intraday models so they stay in lockstep.
#}
{% macro tracked_event_names() -%}
    'ad_impression', 'ad_rewarded', 'booster_used',
    'challenge_change_settings', 'challenge_event', 'challenge_quit',
    'challenge_resume', 'challenge_returned_lost_customer', 'challenge_time_added',
    'change_settings',
    'claim_all_mission_rewards', 'claim_last_welcome_quest_reward',
    'claim_mission_reward', 'claim_season_reward', 'claim_welcome_quest_reward',
    'currency_earned', 'currency_spent', 'daily_reward_claimed',
    'delivery_dash_accept_order', 'delivery_dash_collect_reward',
    'delivery_dash_get_new_orders', 'delivery_dash_instant_finish',
    'delivery_dash_reject_order', 'delivery_restock_food',
    'edit_profile_avatar', 'edit_profile_name',
    'first_open', 'game_started',
    'iap_purchase', 'iap_purchase_failed', 'in_app_purchase',
    'level_completed', 'level_failed', 'level_started',
    'new_player', 'object_level_purchase', 'refresh_quest',
    'screen_change', 'screen_view', 'session_start',
    'staff_level_purchase', 'tutorial_completed', 'tutorial_step',
    'user_engagement'
{%- endmacro %}

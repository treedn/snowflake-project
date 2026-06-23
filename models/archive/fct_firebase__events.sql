{% set sql_statement %}
    select * from {{ ref('stg_interested_event_param_keys') }}
{% endset %}

{%- set param_data = dbt_utils.get_query_results_as_dict(sql_statement) -%}

with 

intermediate_events as ( select * from {{ ref('int_firebase__events') }}),

interested_events as ( select * from {{ ref('stg_interested_events') }}),

interested_event_params as ({{ sql_statement }}),

event_params_pivoted as (
    
    select 

        event_id,

        -- Pivot event parameters: extract common parameters as columns
        
        max(case when intermediate_events.event_param_key = 'value' and intermediate_events.event_name = 'change_settings' 
            then intermediate_events.event_param_double_value end) as change_settings_value,

        max(case when intermediate_events.event_param_key = 'value' and intermediate_events.event_name = 'in_app_purchase' 
            then intermediate_events.event_param_int_value end) as in_app_purchase_value,

        max(case when intermediate_events.event_param_key = 'doubleReward' 
            then intermediate_events.event_param_int_value end) as double_reward,

        max(case when intermediate_events.event_param_key = 'newAvatarId' 
            then intermediate_events.event_param_int_value end) as new_avatar_id,

        max(case when intermediate_events.event_param_key = 'newName' 
            then intermediate_events.event_param_string_value end) as new_name,

        {%- for param_key in param_data['event_param_key'] -%}      

            {% if not param_key in ['value','doubleReward','newAvatarId','newName'] %}

                max(case
                    when intermediate_events.event_param_key = '{{ param_key }}' then 
                        intermediate_events.event_param_{{ param_data['data_type'][loop.index0] }}_value
                end) as {{ param_key }}

                {%- if not loop.last -%}
                    ,
                {%- endif -%}

            {% endif %}
            
        {%- endfor %}

    from intermediate_events

    join interested_events on intermediate_events.event_name = interested_events.event_name

    join interested_event_params on intermediate_events.event_param_key = interested_event_params.event_param_key

    group by event_id

),

event_level_events as (
    select distinct
        * except (
            event_param_key,
            event_param_string_value,
            event_param_int_value,
            event_param_float_value,
            event_param_double_value
        )
    from intermediate_events
),

final as (
    select
        -- Event identification
        event_level_events.event_id,
        event_date,
        event_timestamp,
        event_level_events.event_name,
        
        -- User identification
        user_id,
        user_pseudo_id,
        
        -- Privacy settings
        privacy_info,
        
        -- User properties (kept as struct)
        user_properties,
        
        -- Pivoted event parameters
        change_settings_value,
        in_app_purchase_value,
        double_reward,
        new_avatar_id,
        new_name,
        amount,
        price_dollars,
        time_spent,
        booster_id,
        day_num,
        engagement_time_msec,
        entrances,
        firebase_conversion,
        food_id,
        ga_session_id,
        ga_session_number,
        gem_cost,
        level_id,
        level_num,
        object_id,
        object_level,
        price,
        price_gems,
        quantity,
        quest_id,
        refresh,
        reward_amount,
        staff_id,
        staff_level,
        step_num,
        time,
        timestamp,
        tutorial_id,
        validated,
        ad,
        currency,
        currency_type,
        event_params_pivoted.event_name as params_event_name,
        firebase_event_origin,
        from_screen,
        to_screen,
        item_name,
        location,
        object_name,
        placement,
        product_id,
        product_name,
        reason,
        reward_type,
        source,
        status,
        type,
        with_ads,

        -- Device information
        device_category,
        device_mobile_brand_name,
        device_mobile_model_name,
        device_mobile_os_hardware_model,
        device_operating_system,
        device_operating_system_version,
        device_vendor_id,
        device_language,
        device_is_limited_ad_tracking,
        device_time_zone_offset_seconds,
        
        -- Geographic information
        geo_continent,
        geo_country,
        geo_region,
        geo_city,
        geo_sub_continent,
        geo_metro,
        
        -- App information
        app_info_id,
        app_info_version,
        app_info_install_store,
        app_info_firebase_app_id,
        app_info_install_source,
        
        -- Traffic source
        traffic_source_name,
        traffic_source_medium,
        traffic_source_source,
        
        -- Stream and platform
        stream_id,
        platform
                
    from event_level_events
    join event_params_pivoted on event_level_events.event_id = event_params_pivoted.event_id
)

select * from final
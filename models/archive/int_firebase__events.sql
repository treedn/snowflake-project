with
    staging as (select * from {{ ref("stg_firebase__events") }}),

    unnested_event_params as (
        select
            * except (event_params),
            event_param.key as event_param_key,
            event_param.value.string_value as event_param_string_value,
            event_param.value.int_value as event_param_int_value,
            event_param.value.float_value as event_param_float_value,
            event_param.value.double_value as event_param_double_value
        from staging, unnest(event_params) as event_param
    ),

    final as (
        select
            -- Event identification
            event_id,
            event_date,
            event_timestamp,
            event_name,
            event_previous_timestamp,
            event_value_in_usd,
            event_bundle_sequence_id,
            event_server_timestamp_offset,

            -- User identification
            user_id,
            user_pseudo_id,

            -- Privacy settings
            privacy_info,

            -- Event parameters (unnested)
            event_param_key,
            event_param_string_value,
            event_param_int_value,
            event_param_float_value,
            event_param_double_value,

            -- User properties (kept as struct)
            user_properties,

            -- Device information (unnested)
            device.category as device_category,
            device.mobile_brand_name as device_mobile_brand_name,
            device.mobile_model_name as device_mobile_model_name,
            device.mobile_marketing_name as device_mobile_marketing_name,
            device.mobile_os_hardware_model as device_mobile_os_hardware_model,
            device.operating_system as device_operating_system,
            device.operating_system_version as device_operating_system_version,
            device.vendor_id as device_vendor_id,
            device.advertising_id as device_advertising_id,
            device.language as device_language,
            device.is_limited_ad_tracking as device_is_limited_ad_tracking,
            device.time_zone_offset_seconds as device_time_zone_offset_seconds,
            device.browser as device_browser,
            device.browser_version as device_browser_version,
            device.web_info as device_web_info,

            -- Geographic information (unnested)
            geo.continent as geo_continent,
            geo.country as geo_country,
            geo.region as geo_region,
            geo.city as geo_city,
            geo.sub_continent as geo_sub_continent,
            geo.metro as geo_metro,

            -- App information (unnested)
            app_info.id as app_info_id,
            app_info.version as app_info_version,
            app_info.install_store as app_info_install_store,
            app_info.firebase_app_id as app_info_firebase_app_id,
            app_info.install_source as app_info_install_source,

            -- Traffic source (unnested)
            traffic_source.name as traffic_source_name,
            traffic_source.medium as traffic_source_medium,
            traffic_source.source as traffic_source_source,

            -- Stream and platform
            stream_id,
            platform

        from unnested_event_params
    )

select *
from final

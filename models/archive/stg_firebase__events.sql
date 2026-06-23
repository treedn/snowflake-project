with
    source as (select * from {{ source("firebase_analytics", "events_*") }}),

    renamed as (
        select
            -- Event identification
            {{ dbt_utils.generate_surrogate_key(['event_timestamp', 'event_name', 'user_pseudo_id']) }} as event_id,
            parse_date('%Y%m%d', event_date) as event_date,
            timestamp_micros(event_timestamp) as event_timestamp,
            event_name,
            timestamp_micros(event_previous_timestamp) as event_previous_timestamp,
            event_value_in_usd,
            event_bundle_sequence_id,
            event_server_timestamp_offset,

            -- User identification
            user_id,
            user_pseudo_id,

            -- Privacy settings
            privacy_info,

            -- Event parameters (array of structs - will need to be unnested separately)
            event_params,

            -- User properties (struct)
            user_properties,

            -- Device information (struct)
            device,

            -- Geographic information (struct)
            geo,

            -- App information (struct)
            app_info,

            -- Traffic source (struct)
            traffic_source,

            -- Stream and platform
            stream_id,
            platform,

            -- Event dimensions (array of structs)
            event_dimensions,

            -- Ecommerce (struct)
            ecommerce,

            -- Items (array of structs)
            items

        from source
    )

select *
from renamed


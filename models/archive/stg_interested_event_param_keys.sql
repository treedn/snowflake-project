with
    final as (
        select event_param_key, data_type
        from {{ ref("unique_event_param_key_20260114") }}
        where 1 = 1 and interested = 1
    )

select *
from final

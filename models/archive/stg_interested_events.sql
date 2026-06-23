with
    final as (
        select event_name
        from {{ ref("unique_events_20260114") }}
        where 1 = 1 and interested = 1
    )

select *
from final

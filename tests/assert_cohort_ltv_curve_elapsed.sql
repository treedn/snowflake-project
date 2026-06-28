-- cohort_ltv_daily must only emit a (cohort_date, days_since_install) point once
-- the calendar day cohort_date + days_since_install has FULLY elapsed. Otherwise
-- a partial day leaks into the LTV curve and understates the checkpoint.
-- Returns any row that violates the elapsed-day guard.

select
    cohort_date,
    days_since_install,
    date_add(cohort_date, interval days_since_install day) as as_of_day
from {{ ref('cohort_ltv_daily') }}
where date_add(cohort_date, interval days_since_install day) >= current_date()

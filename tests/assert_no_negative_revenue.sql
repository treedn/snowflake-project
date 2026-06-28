-- Revenue, spend and IAP value are physically non-negative. A negative value
-- signals a sign/units bug upstream. Returns offending rows.

select 'ua_performance_daily' as model_name, 'spend' as metric, spend as value
from {{ ref('ua_performance_daily') }}
where spend < 0

union all
select 'ua_performance_daily', 'revenue', revenue
from {{ ref('ua_performance_daily') }}
where revenue < 0

union all
select 'iap_arpdau_daily', 'iap_revenue', iap_revenue
from {{ ref('iap_arpdau_daily') }}
where iap_revenue < 0

union all
select 'cohort_ltv_daily', 'iap_revenue', iap_revenue
from {{ ref('cohort_ltv_daily') }}
where iap_revenue < 0

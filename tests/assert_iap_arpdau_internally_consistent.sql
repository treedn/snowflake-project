-- The stored rate column `arpdau_iap` must equal its components
-- (iap_revenue / dau). This guards against a future refactor silently changing
-- one expression but not the other. A tiny tolerance absorbs float rounding.
-- Returns rows where the stored rate disagrees with the recomputed rate.

select
    date,
    geo_country,
    app_version,
    spender_segment,
    arpdau_iap,
    safe_divide(iap_revenue, nullif(dau, 0)) as recomputed_arpdau_iap
from {{ ref('iap_arpdau_daily') }}
where abs(
        coalesce(arpdau_iap, 0)
        - coalesce(safe_divide(iap_revenue, nullif(dau, 0)), 0)
      ) > 1e-9

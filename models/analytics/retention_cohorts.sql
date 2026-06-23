with first_touch as (
  select
    user_pseudo_id,
    min(event_date) as cohort_date
  from {{ ref('stg_events') }}
  where user_pseudo_id is not null
    and event_name in ('first_open', 'new_player')
  group by 1
),

cohort_users as (
  select
    ft.user_pseudo_id,
    ft.cohort_date,
    coalesce(e.geo_country, 'unknown') as geo_country,
    coalesce(
      nullif(e.traffic_source_source, ''),
      nullif(e.app_info_install_source, ''),
      'unknown'
    ) as acquisition_source,
    coalesce(e.app_version, 'unknown') as app_version
  from first_touch ft
  join {{ ref('stg_events') }} e
    on e.user_pseudo_id = ft.user_pseudo_id
   and e.event_date = ft.cohort_date
   and e.event_name in ('first_open', 'new_player')
  qualify row_number() over (
    partition by ft.user_pseudo_id
    order by e.event_timestamp asc
  ) = 1
),

user_activity as (
  select distinct
    user_pseudo_id,
    event_date
  from {{ ref('stg_events') }}
  where user_pseudo_id is not null
),

user_iap_value as (
  select
    user_pseudo_id,
    case
      when max(
        case
          when event_name in ('iap_purchase', 'in_app_purchase')
            and coalesce(event_value_in_usd, amount, price_dollars, 0) > 0
            then 1
          else 0
        end
      ) = 1 then 'spender'
      else 'non_spender'
    end as spender_segment,
    sum(coalesce(event_value_in_usd, amount, price_dollars, 0)) as total_iap_value_usd
  from {{ ref('stg_events') }}
  where user_pseudo_id is not null
  group by 1
),

cohort_enriched_users as (
  select
    cu.cohort_date,
    cu.geo_country,
    cu.acquisition_source,
    cu.app_version,
    coalesce(uiv.spender_segment, 'non_spender') as spender_segment,
    cu.user_pseudo_id,
    coalesce(uiv.total_iap_value_usd, 0) as total_iap_value_usd
  from cohort_users cu
  left join user_iap_value uiv
    on uiv.user_pseudo_id = cu.user_pseudo_id
),

retention_base as (
  select
    ceu.cohort_date,
    ceu.geo_country,
    ceu.acquisition_source,
    ceu.app_version,
    ceu.spender_segment,
    ceu.user_pseudo_id,
    date_diff(ua.event_date, ceu.cohort_date, day) as day_offset
  from cohort_enriched_users ceu
  join user_activity ua
    on ua.user_pseudo_id = ceu.user_pseudo_id
  where ua.event_date >= ceu.cohort_date
    and ua.event_date <= date_add(ceu.cohort_date, interval 30 day)
),

retention_metrics as (
  select
    cohort_date,
    geo_country,
    acquisition_source,
    app_version,
    spender_segment,
    count(distinct if(day_offset = 1, user_pseudo_id, null)) as retained_d1_users,
    count(distinct if(day_offset = 3, user_pseudo_id, null)) as retained_d3_users,
    count(distinct if(day_offset = 7, user_pseudo_id, null)) as retained_d7_users,
    count(distinct if(day_offset = 14, user_pseudo_id, null)) as retained_d14_users,
    count(distinct if(day_offset = 30, user_pseudo_id, null)) as retained_d30_users
  from retention_base
  group by 1, 2, 3, 4, 5
),

cohort_user_metrics as (
  select
    cohort_date,
    geo_country,
    acquisition_source,
    app_version,
    spender_segment,
    count(distinct user_pseudo_id) as cohort_size,
    sum(total_iap_value_usd) as total_iap_value_usd
  from cohort_enriched_users
  group by 1, 2, 3, 4, 5
)

select
  cum.cohort_date,
  cum.geo_country,
  cum.acquisition_source,
  cum.app_version,
  cum.spender_segment,
  cum.cohort_size,
  cum.total_iap_value_usd,
  rm.retained_d1_users,
  rm.retained_d3_users,
  rm.retained_d7_users,
  rm.retained_d14_users,
  rm.retained_d30_users
from cohort_user_metrics cum
left join retention_metrics rm
  on rm.cohort_date = cum.cohort_date
 and rm.geo_country = cum.geo_country
 and rm.acquisition_source = cum.acquisition_source
 and rm.app_version = cum.app_version
 and rm.spender_segment = cum.spender_segment
order by cohort_date desc, geo_country, acquisition_source, app_version, spender_segment

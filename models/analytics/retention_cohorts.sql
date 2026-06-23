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

user_spend_status as (
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
    end as spender_segment
  from {{ ref('stg_events') }}
  where user_pseudo_id is not null
  group by 1
),

retention_base as (
  select
    cu.cohort_date,
    cu.geo_country,
    cu.acquisition_source,
    cu.app_version,
    uss.spender_segment,
    cu.user_pseudo_id,
    date_diff(ua.event_date, cu.cohort_date, day) as day_offset
  from cohort_users cu
  left join user_spend_status uss
    on uss.user_pseudo_id = cu.user_pseudo_id
  join user_activity ua
    on ua.user_pseudo_id = cu.user_pseudo_id
  where ua.event_date >= cu.cohort_date
    and ua.event_date <= date_add(cu.cohort_date, interval 30 day)
),

user_iap_value as (
  select
    cu.user_pseudo_id,
    sum(
      case
        when e.event_name in ('iap_purchase', 'in_app_purchase')
          then coalesce(e.event_value_in_usd, e.amount, e.price_dollars, 0)
        else 0
      end
    ) as iap_value_usd
  from cohort_users cu
  join {{ ref('stg_events') }} e
    on e.user_pseudo_id = cu.user_pseudo_id
  where e.event_date >= cu.cohort_date
    and e.event_date <= date_add(cu.cohort_date, interval 30 day)
  group by 1
),

user_retention as (
  select
    cohort_date,
    geo_country,
    acquisition_source,
    app_version,
    coalesce(spender_segment, 'non_spender') as spender_segment,
    user_pseudo_id,
    max(if(day_offset = 1, 1, 0)) as retained_d1_flag,
    max(if(day_offset = 3, 1, 0)) as retained_d3_flag,
    max(if(day_offset = 7, 1, 0)) as retained_d7_flag,
    max(if(day_offset = 14, 1, 0)) as retained_d14_flag,
    max(if(day_offset = 30, 1, 0)) as retained_d30_flag
  from retention_base
  group by 1, 2, 3, 4, 5, 6
),

cohort_metrics as (
  select
    ur.cohort_date,
    ur.geo_country,
    ur.acquisition_source,
    ur.app_version,
    ur.spender_segment,
    count(*) as cohort_size,
    sum(ur.retained_d1_flag) as retained_d1_users,
    sum(ur.retained_d3_flag) as retained_d3_users,
    sum(ur.retained_d7_flag) as retained_d7_users,
    sum(ur.retained_d14_flag) as retained_d14_users,
    sum(ur.retained_d30_flag) as retained_d30_users,
    sum(coalesce(uiv.iap_value_usd, 0)) as total_iap_value_usd
  from user_retention ur
  left join user_iap_value uiv
    on uiv.user_pseudo_id = ur.user_pseudo_id
  group by 1, 2, 3, 4, 5
)

select
  cohort_date,
  geo_country,
  acquisition_source,
  app_version,
  spender_segment,
  cohort_size,
  retained_d1_users,
  retained_d3_users,
  retained_d7_users,
  retained_d14_users,
  retained_d30_users,
  total_iap_value_usd
from cohort_metrics
order by cohort_date desc, geo_country, acquisition_source, app_version, spender_segment

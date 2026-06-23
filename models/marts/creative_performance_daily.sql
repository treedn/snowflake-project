{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'date', 'data_type': 'date'},
    cluster_by=['account_id', 'campaign_id'],
    on_schema_change='append_new_columns'
) }}

-- Creative-level Meta performance: ad-grain spend, engagement, video metrics, and
-- attributed installs/purchases. For network-level paid spend totals prefer
-- ua_performance_daily (Adjust); this mart adds creative breakdowns Adjust can't.
-- Incremental: rebuild last 14 days each run.
select
  date,
  account_id,
  account_name,
  campaign_id,
  campaign_name,
  adset_id,
  adset_name,
  ad_id,
  ad_name,

  impressions,
  reach,
  frequency,
  clicks,
  inline_link_clicks,
  unique_clicks,
  inline_post_engagement,
  spend,
  cpm,
  cpc,
  ctr,
  unique_ctr,

  installs,
  purchases,
  purchase_value,
  link_clicks,
  mobile_app_purchase_roas,

  video_plays,
  video_thruplays,
  video_p25,
  video_p50,
  video_p75,
  video_p100,
  video_avg_time_watched,

  safe_divide(spend, nullif(installs, 0))           as ecpi_meta,
  safe_divide(installs, nullif(clicks, 0))          as cvr_meta,
  safe_divide(video_p100, nullif(video_plays, 0))   as video_completion_rate

from {{ ref('stg_meta_ads__ad_daily') }}
{% if is_incremental() %}
where date >= date_sub(current_date(), interval 14 day)
{% endif %}

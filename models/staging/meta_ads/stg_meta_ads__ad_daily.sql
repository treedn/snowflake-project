{{ config(materialized='view') }}

select
  date_start                                       as date,
  cast(account_id as string)                       as account_id,
  account_name,
  account_currency,
  cast(campaign_id as string)                      as campaign_id,
  campaign_name,
  cast(adset_id as string)                         as adset_id,
  adset_name,
  cast(ad_id as string)                            as ad_id,
  ad_name,
  attribution_setting,

  impressions,
  reach,
  frequency,
  full_view_impressions,
  full_view_reach,
  clicks,
  inline_link_clicks,
  unique_clicks,
  unique_inline_link_clicks,
  inline_post_engagement,
  spend,
  social_spend,
  cpm,
  cpc,
  cpp,
  ctr,
  unique_ctr,
  inline_link_click_ctr,
  unique_inline_link_click_ctr,

  {{ meta_get_action('actions', 'mobile_app_install') }}                          as installs,
  {{ meta_get_action('actions', 'app_custom_event.fb_mobile_purchase') }}         as purchases,
  {{ meta_get_action('action_values', 'app_custom_event.fb_mobile_purchase') }}   as purchase_value,
  {{ meta_get_action('actions', 'link_click') }}                                  as link_clicks,
  {{ meta_get_action('mobile_app_purchase_roas', 'app_custom_event.fb_mobile_purchase') }} as mobile_app_purchase_roas,

  -- Video metrics: extract the standard `video_view` action type.
  {{ meta_get_action('video_play_actions', 'video_view') }}            as video_plays,
  {{ meta_get_action('video_thruplay_watched_actions', 'video_view') }} as video_thruplays,
  {{ meta_get_action('video_p25_watched_actions', 'video_view') }}     as video_p25,
  {{ meta_get_action('video_p50_watched_actions', 'video_view') }}     as video_p50,
  {{ meta_get_action('video_p75_watched_actions', 'video_view') }}     as video_p75,
  {{ meta_get_action('video_p100_watched_actions', 'video_view') }}    as video_p100,
  {{ meta_get_action('video_avg_time_watched_actions', 'video_view') }} as video_avg_time_watched,

  actions,
  action_values,
  unique_actions,
  cost_per_action_type,
  purchase_roas

from {{ source('meta_ads', 'meta_ads_ad_daily') }}

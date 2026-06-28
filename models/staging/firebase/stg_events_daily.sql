{{
  config(
    materialized='incremental',
    partition_by={'field': 'event_date', 'data_type': 'date'},
    cluster_by=['event_name', 'user_pseudo_id'],
    incremental_strategy='insert_overwrite'
  )
}}

-- Finalized events from Firebase events_YYYYMMDD shards.
--
-- Behavior:
--   --full-refresh   : Backfill ALL history from events_*
--   incremental run  : Replace the last 2 days' partitions (handles late-arriving
--                      data; insert_overwrite makes the 2-day window idempotent)
--
-- Recommended schedule: daily after 06:00 UTC
--   dbt run --select stg_events_daily
--
-- The column projection (top-level fields + flattened structs + event_params
-- pivot + PII hashing of user_id) is shared with stg_events_intraday via the
-- ga4_flatten_event_columns() macro so the two shards can never drift apart.

select
  {{ ga4_flatten_event_columns() }}
{#
  Shard resolution: a single real shard at parse/LSP time (execute=false), wildcard
  events_* at execute time. Avoid events_* at parse time — Fusion analyzing the
  wildcard triggers dbt1308 (Storage Read API).
#}
{% set _src = source('firebase_analytics', 'events_wildcard') %}
{% set _shard = (run_started_at - modules.datetime.timedelta(days=2)).strftime('%Y%m%d') %}
from
  {% if not execute %}
    `{{ _src.database }}`.`{{ _src.schema }}`.`events_{{ _shard }}`
  {% else %}
    `{{ _src.database }}`.`{{ _src.schema }}`.`events_*`
  {% endif %}
where
  {% if execute %}
    {% if is_incremental() %}
      -- 2-day lookback: re-process today-2 and today-1 (yesterday).
      -- insert_overwrite replaces those partitions atomically.
      _TABLE_SUFFIX between
        format_date('%Y%m%d', date_sub(current_date(), interval 2 day))
        and format_date('%Y%m%d', date_sub(current_date(), interval 1 day))
    {% else %}
      _TABLE_SUFFIX <= format_date('%Y%m%d', date_sub(current_date(), interval 1 day))
    {% endif %}
    and
  {% endif %}
  event_name in ( {{ tracked_event_names() }} )

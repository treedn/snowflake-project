{{
  config(
    materialized='incremental',
    partition_by={'field': 'event_date', 'data_type': 'date'},
    cluster_by=['event_name', 'user_pseudo_id'],
    incremental_strategy='insert_overwrite'
  )
}}

-- Today's streaming events from Firebase events_intraday_YYYYMMDD.
--
-- Behavior:
--   On every run: insert_overwrite replaces today's partition with the
--   latest snapshot from events_intraday_YYYYMMDD. Idempotent and safe
--   to run as often as needed.
--   Tomorrow this data is replaced by the finalized version in stg_events_daily.
--
-- Recommended schedule: every 15 minutes
--   dbt run --select stg_events_intraday
--
-- Shares the ga4_flatten_event_columns() projection with stg_events_daily so the
-- two shards stay byte-for-byte aligned (required by the UNION ALL in stg_events).

select
  {{ ga4_flatten_event_columns() }}
{#
  Never use events_intraday_* in compiled SQL: dbt Fusion caches sourced_remote schemas
  under target/.lsp using the table id; '*' is illegal in Windows paths (dbt1016).
  Today's shard is sufficient for intraday (same rows as wildcard + _TABLE_SUFFIX).
#}
{% set _intraday_src = source('firebase_analytics', 'events_intraday_wildcard') %}
{% set _intraday_suffix = run_started_at.strftime('%Y%m%d') %}
from
  `{{ _intraday_src.database }}`.`{{ _intraday_src.schema }}`.`events_intraday_{{ _intraday_suffix }}`
where
  event_date = format_date('%Y%m%d', current_date())
  and event_name in ( {{ tracked_event_names() }} )

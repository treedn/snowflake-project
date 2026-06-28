{#
  Single source of truth for the in-app-purchase (IAP) revenue definition.

  These macros centralise the rule that was previously copy-pasted across
  iap_arpdau_daily, cohort_ltv_daily and the analytics layer. Keeping it in one
  place guarantees every mart/metric agrees on:

    * which events count as monetised IAP events, and
    * how a single purchase is valued in USD.

  IMPORTANT — the generic `amount` event param is intentionally NOT part of the
  value expression. On non-IAP events (`currency_earned` / `currency_spent`) it
  carries in-game *coin* amounts and would inflate USD revenue by orders of
  magnitude. (This was the bug in analytics.retention_cohorts; see that model.)
#}

{# Events that represent a real monetised in-app purchase. #}
{% macro iap_event_names() -%}
    ('iap_purchase', 'in_app_purchase')
{%- endmacro %}

{#
  USD value of an IAP event: prefer Firebase's reconciled USD value, fall back
  to the client-reported price in dollars, else 0. Pass column aliases if your
  CTE renames them.
#}
{% macro iap_value_usd(value_usd_col='event_value_in_usd', price_dollars_col='price_dollars') -%}
    coalesce({{ value_usd_col }}, {{ price_dollars_col }}, 0)
{%- endmacro %}

{#
  Boolean: is this row a monetised IAP event (value > 0)?
  `event_name_col` lets callers pass an aliased column.
#}
{% macro is_iap_revenue_event(event_name_col='event_name', value_usd_col='event_value_in_usd', price_dollars_col='price_dollars') -%}
    {{ event_name_col }} in {{ iap_event_names() }}
    and {{ iap_value_usd(value_usd_col, price_dollars_col) }} > 0
{%- endmacro %}

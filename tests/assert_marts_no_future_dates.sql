-- No mart should contain rows dated in the future. A future-dated row almost
-- always means a timezone bug, a bad source partition, or a clock-skewed
-- ingestion run. Returns offending rows (test fails if any exist).

{% set dated_marts = [
  ('ua_performance_daily', 'date'),
  ('engagement_daily', 'date'),
  ('creative_performance_daily', 'date'),
  ('ua_funnel_daily', 'date'),
  ('iap_arpdau_daily', 'date'),
  ('session_depth_daily', 'date'),
  ('tutorial_funnel_daily', 'date'),
  ('cohort_ltv_daily', 'cohort_date'),
] %}

{% for model_name, date_col in dated_marts %}
select
    '{{ model_name }}' as model_name,
    {{ date_col }}     as offending_date
from {{ ref(model_name) }}
where {{ date_col }} > current_date()
{% if not loop.last %}union all{% endif %}
{% endfor %}

-- Native date spine (avoids dbt_utils date_spine + fetch_result, which can hit dbt1308 on BigQuery).
select day as date_day
from unnest(generate_date_array(date '2025-10-01', date '2027-01-01')) as day

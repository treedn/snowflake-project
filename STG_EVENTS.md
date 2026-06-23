# stg_events

Denormalized events table for Chef Master game analytics.

**Location**: `chef-master-8f916.<staging schema>.stg_events` (schema name depends on dbt target)
**Source**: Firebase Analytics / GA4 export (`analytics_448269098.events_*` and `events_intraday_*`)
**Grain**: One row per event
**Partitioned by**: `event_date`
**Clustered by**: `event_name`, `user_pseudo_id`
**Managed by**: three dbt models in [models/staging/firebase/](models/staging/firebase/)

---

## What this table does

Flattens raw Firebase event data into a single wide table. All `event_params` are pivoted into typed columns and all nested structs (`device`, `geo`, `app_info`, `traffic_source`) are flattened. No UNNEST or joins needed at query time.

## How it runs

Three dbt models work together:

| Model | Materialization | Source | Schedule | What it does |
|-------|----------------|--------|----------|--------------|
| [stg_events_daily](models/staging/firebase/stg_events_daily.sql) | incremental (insert_overwrite) | `events_*` | Daily after 06:00 UTC | Replaces yesterday's partition with finalized data; `--full-refresh` backfills all history |
| [stg_events_intraday](models/staging/firebase/stg_events_intraday.sql) | table | `events_intraday_*` | Every 15 minutes | Always rebuilds today's snapshot |
| [stg_events](models/staging/firebase/stg_events.sql) | view | UNION of the two above | n/a | Unified view downstream models query |

**Recommended commands** (orchestrate via dbt Cloud, Cloud Composer, GitHub Actions, or cron):

```bash
# Initial backfill (one time)
dbt run --select stg_events_daily --full-refresh

# Daily, after 06:00 UTC
dbt run --select stg_events_daily

# Every 15 minutes
dbt run --select stg_events_intraday
```

In downstream dbt models and analyses, reference the unified view with `{{ ref('stg_events') }}`.

---

## Column mapping

### From top-level event fields

| stg_events column | Raw events column |
|-------------------|-------------------|
| `event_date` | `PARSE_DATE('%Y%m%d', event_date)` |
| `event_timestamp` | `TIMESTAMP_MICROS(event_timestamp)` |
| `event_name` | `event_name` |
| `event_value_in_usd` | `event_value_in_usd` |
| `user_id` | `user_id` |
| `user_pseudo_id` | `user_pseudo_id` |
| `user_first_touch_timestamp` | `TIMESTAMP_MICROS(user_first_touch_timestamp)` |
| `stream_id` | `stream_id` |
| `platform` | `platform` |

### From `device` struct

| stg_events column | Raw events column |
|-------------------|-------------------|
| `device_category` | `device.category` |
| `device_mobile_brand_name` | `device.mobile_brand_name` |
| `device_mobile_model_name` | `device.mobile_model_name` |
| `device_mobile_marketing_name` | `device.mobile_marketing_name` |
| `device_mobile_os_hardware_model` | `device.mobile_os_hardware_model` |
| `device_operating_system` | `device.operating_system` |
| `device_operating_system_version` | `device.operating_system_version` |
| `device_language` | `device.language` |
| `device_is_limited_ad_tracking` | `device.is_limited_ad_tracking` |
| `device_time_zone_offset_seconds` | `device.time_zone_offset_seconds` |

### From `geo` struct

| stg_events column | Raw events column |
|-------------------|-------------------|
| `geo_continent` | `geo.continent` |
| `geo_country` | `geo.country` |
| `geo_region` | `geo.region` |
| `geo_city` | `geo.city` |
| `geo_sub_continent` | `geo.sub_continent` |
| `geo_metro` | `geo.metro` |

### From `app_info` struct

| stg_events column | Raw events column |
|-------------------|-------------------|
| `app_info_id` | `app_info.id` |
| `app_version` | `app_info.version` |
| `app_info_install_store` | `app_info.install_store` |
| `app_info_firebase_app_id` | `app_info.firebase_app_id` |
| `app_info_install_source` | `app_info.install_source` |

### From `traffic_source` struct

| stg_events column | Raw events column |
|-------------------|-------------------|
| `traffic_source_name` | `traffic_source.name` |
| `traffic_source_medium` | `traffic_source.medium` |
| `traffic_source_source` | `traffic_source.source` |

### From `event_params` array (pivoted via UNNEST)

Each column is extracted as: `(SELECT value.<type>_value FROM UNNEST(event_params) WHERE key = '<key>')`

| stg_events column | event_params key | value type |
|-------------------|-----------------|------------|
| `booster_id` | booster_id | int |
| `day_num` | day_num | int |
| `double_reward` | doubleReward | int |
| `engagement_time_msec` | engagement_time_msec | int |
| `entrances` | entrances | int |
| `firebase_conversion` | firebase_conversion | int |
| `food_id` | food_id | int |
| `ga_session_id` | ga_session_id | int |
| `ga_session_number` | ga_session_number | int |
| `gem_cost` | gem_cost | int |
| `level_id` | level_id | int |
| `level_num` | level_num | int |
| `new_avatar_id` | newAvatarId | int |
| `object_id` | object_id | int |
| `object_level` | object_level | int |
| `price` | price | int |
| `price_gems` | price_gems | int |
| `quantity` | quantity | int |
| `quest_id` | quest_id | int |
| `refresh` | refresh | int |
| `reward_amount` | reward_amount | int |
| `staff_id` | staff_id | int |
| `staff_level` | staff_level | int |
| `step_num` | step_num | int |
| `time` | time | int |
| `param_timestamp` | timestamp | int |
| `tutorial_id` | tutorial_id | int |
| `validated` | validated | int |
| `param_value` | value | int |
| `amount` | amount | double |
| `price_dollars` | price_dollars | double |
| `time_spent` | time_spent | double |
| `ad` | ad | string |
| `currency` | currency | string |
| `currency_type` | currency_type | string |
| `param_event_name` | event_name | string |
| `firebase_event_origin` | firebase_event_origin | string |
| `from_screen` | from_screen | string |
| `item_name` | item_name | string |
| `location` | location | string |
| `new_name` | newName | string |
| `object_name` | object_name | string |
| `placement` | placement | string |
| `product_id` | product_id | string |
| `product_name` | product_name | string |
| `reason` | reason | string |
| `reward_type` | reward_type | string |
| `param_source` | source | string |
| `status` | status | string |
| `to_screen` | to_screen | string |
| `type` | type | string |
| `with_ads` | with_ads | string |

Renamed columns (to avoid collision with top-level fields or reserved words): `param_timestamp`, `param_value`, `param_event_name`, `param_source`, `new_avatar_id`, `new_name`, `double_reward`.

---

## Events

45 events are included:

| Category | Events |
|----------|--------|
| **Gameplay** | `level_started`, `level_completed`, `level_failed`, `booster_used`, `game_started` |
| **Challenge** | `challenge_event`, `challenge_change_settings`, `challenge_quit`, `challenge_resume`, `challenge_returned_lost_customer`, `challenge_time_added` |
| **Economy** | `currency_earned`, `currency_spent` |
| **IAP** | `iap_purchase`, `iap_purchase_failed`, `in_app_purchase` |
| **Upgrades** | `staff_level_purchase`, `object_level_purchase` |
| **Rewards** | `claim_mission_reward`, `claim_all_mission_rewards`, `claim_season_reward`, `claim_welcome_quest_reward`, `claim_last_welcome_quest_reward`, `daily_reward_claimed` |
| **Delivery Dash** | `delivery_dash_accept_order`, `delivery_dash_collect_reward`, `delivery_dash_get_new_orders`, `delivery_dash_instant_finish`, `delivery_dash_reject_order`, `delivery_restock_food` |
| **Tutorial** | `tutorial_step`, `tutorial_completed` |
| **Profile** | `edit_profile_avatar`, `edit_profile_name`, `change_settings` |
| **Navigation** | `screen_change`, `screen_view` |
| **Lifecycle** | `new_player`, `first_open`, `session_start`, `user_engagement` |
| **Ads** | `ad_impression`, `ad_rewarded` |
| **Other** | `refresh_quest` |

---

## Example queries

### 1. Level fail rate by version

```sql
SELECT
  app_version,
  level_id,
  COUNT(DISTINCT CASE WHEN event_name = 'level_started' THEN user_pseudo_id END) AS users_started,
  COUNT(DISTINCT CASE WHEN event_name = 'level_failed' THEN user_pseudo_id END)  AS users_failed,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'level_failed' THEN user_pseudo_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'level_started' THEN user_pseudo_id END)
  ) AS fail_rate
FROM {{ ref('stg_events') }}
WHERE event_name IN ('level_started', 'level_failed')
  AND geo_country != 'Croatia'
  AND level_id IS NOT NULL
GROUP BY app_version, level_id
ORDER BY fail_rate DESC
```

### 2. Booster usage by level (IAP vs free players)

```sql
WITH iap_players AS (
  SELECT DISTINCT user_pseudo_id
  FROM {{ ref('stg_events') }}
  WHERE event_name = 'iap_purchase' AND price_dollars > 0
)
SELECT
  e.level_id,
  e.booster_id,
  COUNT(*) AS usage_count,
  COUNT(DISTINCT e.user_pseudo_id) AS unique_users,
  COUNTIF(p.user_pseudo_id IS NOT NULL) AS iap_usage,
  COUNTIF(p.user_pseudo_id IS NULL) AS free_usage
FROM {{ ref('stg_events') }} e
LEFT JOIN iap_players p ON e.user_pseudo_id = p.user_pseudo_id
WHERE e.event_name = 'booster_used'
  AND e.booster_id IS NOT NULL
GROUP BY e.level_id, e.booster_id
ORDER BY usage_count DESC
```

### 3. Coins earned vs spent per level

```sql
SELECT
  level_id,
  SUM(CASE WHEN event_name = 'currency_earned' THEN amount ELSE 0 END) AS total_earned,
  SUM(CASE WHEN event_name = 'currency_spent' THEN amount ELSE 0 END)  AS total_spent,
  SUM(CASE WHEN event_name = 'currency_earned' THEN amount ELSE 0 END)
    - SUM(CASE WHEN event_name = 'currency_spent' THEN amount ELSE 0 END) AS net_balance,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM {{ ref('stg_events') }}
WHERE event_name IN ('currency_earned', 'currency_spent')
  AND currency_type = 'Coins'
  AND level_id IS NOT NULL
GROUP BY level_id
ORDER BY level_id
```

### 4. IAP revenue by product and level

```sql
SELECT
  app_version,
  level_id,
  item_name AS product_name,
  SUM(price_dollars) AS total_revenue,
  COUNT(*) AS purchase_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_buyers
FROM {{ ref('stg_events') }}
WHERE event_name = 'iap_purchase'
  AND price_dollars > 0
GROUP BY app_version, level_id, item_name
ORDER BY total_revenue DESC
```

### 5. Player progression: max level per active day

```sql
WITH player_days AS (
  SELECT
    user_pseudo_id,
    event_date,
    DENSE_RANK() OVER (PARTITION BY user_pseudo_id ORDER BY event_date) - 1 AS active_day,
    MAX(level_id) AS max_level
  FROM {{ ref('stg_events') }}
  WHERE event_name NOT IN ('user_engagement', 'screen_change')
    AND level_id IS NOT NULL
  GROUP BY user_pseudo_id, event_date
)
SELECT
  active_day,
  COUNT(DISTINCT user_pseudo_id) AS players,
  AVG(max_level) AS avg_max_level,
  APPROX_QUANTILES(max_level, 2)[OFFSET(1)] AS median_max_level
FROM player_days
WHERE active_day <= 14
GROUP BY active_day
ORDER BY active_day
```

### 6. Daily active users and revenue

```sql
SELECT
  event_date,
  COUNT(DISTINCT user_pseudo_id) AS dau,
  COUNT(DISTINCT CASE WHEN event_name = 'iap_purchase' AND price_dollars > 0
        THEN user_pseudo_id END) AS paying_users,
  SUM(CASE WHEN event_name = 'iap_purchase' THEN price_dollars ELSE 0 END) AS daily_revenue
FROM {{ ref('stg_events') }}
WHERE event_name NOT IN ('user_engagement', 'screen_change', 'screen_view')
GROUP BY event_date
ORDER BY event_date DESC
```

---

## Common patterns

**Exclude test traffic**: Most queries filter `AND geo_country != 'Croatia'` to remove internal testing.

**Level attribution**: This table does NOT pre-compute level attribution. Events like `booster_used`, `currency_earned`, `iap_purchase` carry their own `level_id` only if the game sends it. If `level_id` is NULL for these events, you need a window function to infer it from the nearest `level_started`:

```sql
LAST_VALUE(level_id IGNORE NULLS) OVER (
  PARTITION BY user_pseudo_id
  ORDER BY event_timestamp
  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS attributed_level_id
```

**Active day calculation**: Use `DENSE_RANK` on distinct event dates per user:

```sql
DENSE_RANK() OVER (
  PARTITION BY user_pseudo_id ORDER BY event_date
) - 1 AS active_day
```

**IAP player segmentation**: Identify paying users for segmentation:

```sql
user_pseudo_id IN (
  SELECT DISTINCT user_pseudo_id
  FROM {{ ref('stg_events') }}
  WHERE event_name = 'iap_purchase' AND price_dollars > 0
)
```

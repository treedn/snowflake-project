# Marketing Analytics Marts

Unified UA, engagement, LTV, and creative-performance models built from
`raw.adjust_report`, `raw.meta_ads_*`, and `raw.unity_*` (ingested by the
`zero1-data` Python pipeline).

---

## TL;DR

```sql
-- "Show me daily UA performance and engagement for the US on iOS, last 14 days"
SELECT *
FROM `chef-master-8f916.dbt_tri_marts.overview_daily`
WHERE platform = 'ios'
  AND country  = 'US'
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
ORDER BY date;
```

`overview_daily` is the dashboard-friendly join of UA + engagement.
For deeper questions (network/campaign splits, creatives, cohort LTV), query
the dedicated marts below.

---

## 1. Architecture

```
raw.* (zero1-data ingestion, partition_by=day, WRITE_TRUNCATE last 7d)
  │
  ├── staging.stg_adjust__report                (view, passthrough + snake_case)
  ├── staging.stg_meta_ads__campaign_daily      (view, action arrays unpacked)
  ├── staging.stg_meta_ads__ad_daily            (view, video metrics unpacked)
  └── staging.stg_unity__analytics_daily        (view, camelCase → snake_case)
         │
         └── marts.*  (incremental tables, partition_by=date, last 14d window)
              ├── ua_performance_daily          ← Adjust   — UA spend / installs / ROAS / IAP+ad revenue split
              ├── engagement_daily              ← Unity    — DAU / retention / ARPDAU
              ├── iap_arpdau_daily              ← Firebase — IAP × geo × app_version × spender_segment
              ├── cohort_ltv_daily              ← Firebase — IAP cohort LTV × days_since_install × geo × app_version
              ├── creative_performance_daily    ← Meta     — ad-grain spend + video metrics
              ├── ua_funnel_daily               ← Adjust   — impr → click → install → purchase
              ├── session_depth_daily           ← Firebase — session distribution × geo × app_version × platform
              ├── tutorial_funnel_daily         ← Firebase — tutorial step / completion funnel × tutorial_id × step_num
              └── overview_daily                (view)     — UA × engagement, single dashboard target

For cohort retention by app_version / geo / acquisition source, see
`analytics.retention_cohorts` (sourced from Firebase `stg_events`).
```

**Refresh model**: marts are `materialized='incremental'` with
`incremental_strategy='insert_overwrite'`. Each scheduled run rebuilds the last
14 days and overwrites those partitions. Older partitions are frozen until you
`dbt run --full-refresh`.

---

## 2. Mart reference

### `ua_performance_daily`
**Grain**: `(date, app, platform, country, network, campaign, campaign_id)`
**Source**: `stg_adjust__report` — Adjust ingests Meta cost natively, so this is
the single source of truth for paid spend joined to attributed
installs/revenue/ROAS.

| Metric | Notes |
|---|---|
| `installs`, `paid_installs`, `organic_installs` | From Adjust attribution |
| `spend` | Ad-network cost as Adjust sees it |
| `revenue` | IAP + tracked-event revenue (Adjust's "non-ad" revenue field) |
| `cohort_revenue` | Adjust same-day cohort revenue |
| `ad_revenue` | Ad mediation revenue (e.g. AdMob, AppLovin) |
| `all_revenue` | `revenue + ad_revenue` (Adjust's combined total) |
| `impressions`, `clicks` | Network-reported |
| `ctr`, `cvr`, `ecpm`, `ecpc`, `ecpi` | Recomputed from sums |
| `arpdau` | IAP ARPDAU = `revenue / daus` |
| `arpdau_ad` | Ad ARPDAU = `ad_revenue / daus` |
| `arpdau_all` | Combined ARPDAU = `all_revenue / daus` |
| `iap_share`, `ad_share` | Revenue mix (`revenue / all_revenue`, `ad_revenue / all_revenue`) |
| `roas`, `roas_ad`, `roi` | Recomputed from sums |

### `engagement_daily`
**Grain**: `(date, country, platform)` — rolled up from clientVersion.
**Source**: `stg_unity__analytics_daily`.
**Caveat**: Unity returns one row per `clientVersion`; users on multiple
versions in a day are double-counted. DAU/payers are upper bounds.
Retention/session rates are **DAU-weighted**. To get exact totals, re-pull
`unity_data_gateway` without `clientVersion` in `groupBy`.

| Metric | Notes |
|---|---|
| `dau`, `new_users`, `wau`, `mau`, `payers` | See caveat above |
| `total_revenue`, `iap_revenue`, `total_transactions` | In-game ledger |
| `arpdau`, `arppu`, `revenue_per_transaction` | Recomputed from sums |
| `d1_retention`, `d7_retention`, `d30_retention` | DAU-weighted |
| `sessions`, `sessions_per_user`, `avg_session_length`, `play_time_per_user` | DAU-weighted |

### Cohort retention → `analytics.retention_cohorts`

Not a mart. Cohort retention lives in the analytics layer at
`chef-master-8f916.analytics.retention_cohorts`, sourced from `stg_events` (Firebase).

**Grain**: `(cohort_date, geo_country, acquisition_source, app_version, spender_segment)`
**Cohort key**: first `first_open` or `new_player` event per `user_pseudo_id`.
**Retention definition**: user fired any tracked event on `cohort_date + N` exact.
**Columns**: `cohort_size`, `total_iap_value_usd`, `retained_d{1,3,7,14,30}_users`. Compute rates as `retained_dN_users / cohort_size` in your query.

`acquisition_source` = `coalesce(traffic_source_source, app_info_install_source, 'unknown')` from Firebase. This is Firebase's view of attribution — it differs from Adjust's. Use `ua_performance_daily` if you need Adjust-attributed campaign performance.

### `creative_performance_daily`
**Grain**: `(date, account_id, campaign_id, adset_id, ad_id)`
**Source**: `stg_meta_ads__ad_daily`.
**Use for**: creative-level analysis (video completion, A/B, fatigue) that
Adjust can't show. Don't sum `spend` here for network totals — use
`ua_performance_daily` instead (Adjust de-dupes platform→Meta double-attribution).

| Metric | Notes |
|---|---|
| `impressions`, `reach`, `frequency`, `clicks`, `link_clicks` | Meta-reported |
| `spend`, `cpm`, `cpc`, `ctr` | Meta-reported |
| `installs`, `purchases`, `purchase_value`, `mobile_app_purchase_roas` | Extracted from `actions` array (`mobile_app_install`, `app_custom_event.fb_mobile_purchase`) |
| `video_plays`, `video_thruplays`, `video_p25/50/75/100` | Per-quartile completion counts |
| `video_completion_rate` | `video_p100 / video_plays` |
| `ecpi_meta`, `cvr_meta` | Meta's view; will differ from Adjust's |

### `iap_arpdau_daily`
**Grain**: `(date, geo_country, app_version, spender_segment)`
**Source**: `stg_events` (Firebase).
**Purpose**: complements `ua_performance_daily`. Adjust can't carry `app_version` (not in ingestion) or `spender_segment` (aggregate, no per-user); this mart provides those dims at IAP scope. Long format — `spender_segment` is a dimension, not split into columns.

| Metric | Notes |
|---|---|
| `dau` | `COUNT(DISTINCT user_pseudo_id)` per cell |
| `iap_revenue` | `SUM` of `event_value_in_usd` / `price_dollars` on `iap_purchase` and `in_app_purchase` events ONLY |
| `iap_transactions` | Count of IAP events with value > 0 |
| `arpdau_iap` | `iap_revenue / dau` — recompute when aggregating |

**Important caveats**:
- `amount` event param is **deliberately excluded** from IAP value. It carries `currency_earned`/`currency_spent` coin amounts on non-IAP events; including it would inflate totals by orders of magnitude. (This is the bug currently in `analytics.retention_cohorts.total_iap_value_usd`.)
- **Ad revenue is NOT in this mart.** Firebase ad events have no $ value. For ad revenue use `ua_performance_daily` (Adjust scope).
- `spender_segment` reflects status **as of run time** (any IAP > 0 ever). A user who first spends today gets reclassified across all their prior rows on the next incremental rebuild.

### `cohort_ltv_daily`
**Grain**: `(cohort_date, days_since_install, geo_country, app_version)`
**Source**: `stg_events` (Firebase).
**Purpose**: cohort LTV curves by install date. Stores the per-DSI numerators (`iap_revenue`, `iap_transactions`, `paying_users`) and the `cohort_size` denominator. Long format on purpose — adding new checkpoints (D45, D60, …) is a `max_dsi` bump, no schema change. `geo_country` and `app_version` are frozen at install.

| Metric | Notes |
|---|---|
| `cohort_size` | Distinct `user_pseudo_id` per (cohort_date, geo_country, app_version) — denominator for LTV |
| `iap_revenue` | Per-DSI revenue, NOT cumulative. Same IAP definition as `iap_arpdau_daily` |
| `iap_transactions` | Per-DSI count of paying events |
| `paying_users` | Per-DSI distinct paying users |

**How to read LTV**: cumulative LTV at day N is a running sum, so always recompute:

```sql
SELECT cohort_date, geo_country, app_version,
       ANY_VALUE(cohort_size) AS cohort_size,
       SAFE_DIVIDE(SUM(IF(days_since_install <= 7,  iap_revenue, 0)), ANY_VALUE(cohort_size)) AS ltv_d7,
       SAFE_DIVIDE(SUM(IF(days_since_install <= 14, iap_revenue, 0)), ANY_VALUE(cohort_size)) AS ltv_d14,
       SAFE_DIVIDE(SUM(IF(days_since_install <= 30, iap_revenue, 0)), ANY_VALUE(cohort_size)) AS ltv_d30
FROM `chef-master-8f916.marts.cohort_ltv_daily`
GROUP BY 1, 2, 3;
```

**Important caveats**:
- **IAP only.** Firebase ad events have no $ value. Use Adjust cohort revenue (not currently ingested) for ad-LTV.
- Cohort definition uses `first_open` only — `analytics.retention_cohorts` also includes `new_player`, so its cohort sizes can be marginally larger.
- `geo_country` / `app_version` are install-time, not event-time. A user who installs on 0.10 and purchases on 0.11 contributes to the 0.10 cohort.
- A `(cohort_date, days_since_install)` row only appears once the calendar day `cohort_date + days_since_install` has fully elapsed. So for `cohort_date = today - 30`, `days_since_install = 30` is not yet emitted.
- Croatia is excluded at install (matches the rest of the marts).
- Curve horizon is `[0, 30]`. Bump `max_dsi` in the model and `--full-refresh` to extend.
- Incremental window is 44 days (`max_dsi + 14`); older cohort partitions are frozen.

### `session_depth_daily`
**Grain**: `(date, platform, app_version, geo_country)`
**Source**: `stg_events` (Firebase).
**Purpose**: distribution of session shape (depth, length, levels played, frequency) across releases and geos. One row per cell with avg + percentile columns per metric, no histogram explosion.

| Metric | Distribution columns | Notes |
|---|---|---|
| `events_per_session` | `avg_`, `p25_`, `p50_`, `p75_`, `p90_`, `p99_events_per_session` | Excludes `user_engagement`, `screen_change`, `screen_view` (Firebase auto-fired noise) |
| `duration_seconds` | `avg_`, `p25_`…`p99_duration_seconds` | `max(event_timestamp) - min(event_timestamp)` per session, in seconds. Uses ALL events (incl. noise) so the session window is accurate |
| `levels_per_session` | `avg_`, `p25_`…`p99_levels_per_session` | `count(distinct level_id)` on `level_started` events |
| `sessions_per_user` | `avg_`, `p25_`…`p99_sessions_per_user` | `count(distinct ga_session_id)` per (user, date) cell |
| `sessions`, `user_days` | denominators | `sessions` = sessions in cell; `user_days` = (user × cell) rows |

**Important caveats**:
- A session = `(user_pseudo_id, ga_session_id)`, attributed to the date of its **first event**. Sessions that span midnight count once on the start date.
- For percentiles, `APPROX_QUANTILES(col, 100)` is used — quantile values are approximate (within ~1% of true quantile on this data volume). Don't sum percentile columns across rows; recompute from raw events if precise quantiles are needed.
- For `sessions_per_user`, a user with sessions across multiple cells in a day contributes one row per cell, so platform/geo splits stay consistent. Adding `sessions_per_user` rows across cells does **not** equal that user's all-day session count.
- Croatia excluded.
- Sessions whose first event predates the 14d incremental window get partially aggregated (all events before the window are dropped). Most sessions are intra-day, so this is a boundary-only artifact.

### `tutorial_funnel_daily`
**Grain**: `(date, app_version, geo_country, platform, tutorial_id, step_num)`
**Source**: `stg_events` (Firebase).
**Purpose**: per-tutorial funnel for FTUE / onboarding analysis. Long format — `step_num = 1..N` rows are `tutorial_step` events, `step_num = NULL` rows are `tutorial_completed` events. Use to compute completion rate per tutorial and step-level drop-off curves.

| Metric | Notes |
|---|---|
| `users` | `COUNT(DISTINCT user_pseudo_id)` per cell — exact within a cell |
| `events` | Raw event count per cell. `events > users` indicates step replay |

**Recipes:**

```sql
-- Per-tutorial completion rate (last 14d, all geos / versions / platforms)
SELECT
  tutorial_id,
  SUM(IF(step_num = 1,    users, 0)) AS users_started,
  SUM(IF(step_num IS NULL, users, 0)) AS users_completed,
  SAFE_DIVIDE(
    SUM(IF(step_num IS NULL, users, 0)),
    NULLIF(SUM(IF(step_num = 1, users, 0)), 0)
  ) AS completion_rate
FROM `chef-master-8f916.marts.tutorial_funnel_daily`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
GROUP BY tutorial_id
ORDER BY tutorial_id;

-- Drop-off curve for a tutorial
SELECT step_num, SUM(users) AS users
FROM `chef-master-8f916.marts.tutorial_funnel_daily`
WHERE tutorial_id = 40000
  AND step_num IS NOT NULL
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
GROUP BY step_num
ORDER BY step_num;
```

**Important caveats**:
- "Started" anchor is `step_num = 1`. A small number of sessions fire `step_num >= 2` without a step 1 (mid-tutorial join / event loss); completion rate using step 1 as denominator is therefore an upper bound.
- `users` is exact within a cell. Summing across cells (e.g. across app_versions or geos) double-counts users who span cells — same caveat as `engagement_daily.dau`. For exact cross-cell rates, recompute from `stg_events` at user grain.
- `tutorial_id` values (40000–40022 in current data) are numeric — game-team naming is not in this layer; map externally if needed.
- Croatia excluded.

### `ua_funnel_daily`
**Grain**: `(date, app, platform, country, network, campaign)`
**Source**: `stg_adjust__report`.

| Stage / rate | Definition |
|---|---|
| `impressions → clicks` | `impr_to_click_rate` |
| `clicks → installs` | `click_to_install_rate` |
| `installs → revenue events` | `install_to_purchase_rate` |
| `installs → any event` | `install_to_event_rate` |
| `cpi`, `install_arpu_d0` | Per-install economics |

> ⚠️ This is the **acquisition** funnel.
> In-game level/progression funnels need player-event data (Firebase events) and
> are not derivable from these sources. Use the `firebase` staging layer for those.

### `overview_daily`
**Grain**: `(date, app, platform, country)`
**Type**: view (no storage cost; recomputes on read).
Joins `ua_performance_daily` + `engagement_daily`. Engagement does not carry
network/campaign — query `ua_performance_daily` directly when those splits are
needed.

---

## 3. Which mart for which question

| Question | Use this mart | Key columns |
|---|---|---|
| Game ARPDAU / overall monetization | `engagement_daily` | `arpdau`, `arppu`, `total_revenue` |
| Revenue + ARPDAU split IAP vs ads (paid-UA scope, by network) | `ua_performance_daily` | `revenue` (IAP), `ad_revenue`, `all_revenue`, `arpdau`, `arpdau_ad`, `arpdau_all`, `iap_share`, `ad_share` |
| IAP revenue + ARPDAU by app_version × spender_segment × geo | `iap_arpdau_daily` | `iap_revenue`, `arpdau_iap`, `dau`, `iap_transactions` |
| Per-network / per-campaign ROAS | `ua_performance_daily` | `roas`, `spend`, `cohort_revenue` |
| Per-creative video performance | `creative_performance_daily` | `video_completion_rate`, `ctr`, `cpc` |
| Retention by activity day | `engagement_daily` | `d1_retention`, `d7_retention`, `d30_retention` |
| Retention by install cohort (segment by geo / source / app_version) | `analytics.retention_cohorts` | `retained_d{1,3,7,14,30}_users`, `cohort_size` |
| LTV by install cohort (IAP scope, by geo / app_version, D0..D30) | `cohort_ltv_daily` | `iap_revenue`, `cohort_size`, `days_since_install` — recompute cumulative LTV with `SUM(iap_revenue WHERE days_since_install <= N) / cohort_size` |
| LTV including ad revenue | (not currently available — Firebase ad events carry no $ value; needs Adjust cohort API) | — |
| Funnel (impressions → installs → purchase) | `ua_funnel_daily` | rates + counts |
| Session depth / length / frequency distribution by platform × app_version × geo | `session_depth_daily` | `events_per_session`, `duration_seconds`, `levels_per_session`, `sessions_per_user` (avg + p25/p50/p75/p90/p99 each) |
| FTUE / per-tutorial completion rate + step-level drop-off | `tutorial_funnel_daily` | `users` per (tutorial_id, step_num); step_num NULL = completion |
| One-stop dashboard snapshot | `overview_daily` | UA + engagement on shared dims |

### Source-of-truth precedence

Use **Adjust** (`ua_performance_daily`, `ua_funnel_daily`) when the question is
"how did *this UA campaign* perform?" — Adjust is the only system that joins
spend to attributed installs to revenue.

Use **Unity Analytics** (`engagement_daily`) when the question is "how is *the
game* doing?" — overall DAU, retention, monetization, regardless of UA channel.

Use **Meta Ads** (`creative_performance_daily`) when the question is about *the
ad creative itself* — video completion, format, age/gender splits.

These will not match on revenue or ARPDAU. That is expected, not a bug — they
measure different scopes:

- **Adjust ARPDAU**: revenue from users attributed to a campaign / DAU of those users (only the events Adjust SDK sees).
- **Unity ARPDAU**: total in-game revenue / total DAU (everyone, every channel).
- **Meta purchase ROAS**: Meta's own conversion-window attribution — overstates vs Adjust because of view-through credit.

If a dashboard mixes them, **label clearly** (`ARPDAU (overall)` vs `ARPDAU (paid UA)`).

---

## 4. Metric usage rules

### Rule 1 — Sums vs rates

| Type | Examples | How to aggregate |
|---|---|---|
| **Counts / sums** | `installs`, `spend`, `revenue`, `daus`, `clicks`, `impressions` | `SUM()` away |
| **Rates / ratios** | `arpdau`, `roas`, `roi`, `ctr`, `cvr`, `ecpi`, `*_retention`, `*_completion_rate` | Read directly at exact grain, or **recompute from components** |

### Rule 2 — Never `AVG()` a rate

```sql
-- ❌ WRONG — gives every row equal weight (a 1-DAU day == a 10k-DAU day)
SELECT AVG(arpdau) FROM engagement_daily WHERE country = 'US';

-- ✅ RIGHT — recompute from components
SELECT SUM(total_revenue) / NULLIF(SUM(dau), 0) AS arpdau
FROM engagement_daily WHERE country = 'US';
```

The marts deliberately store both numerator and denominator so you can
recompute correctly.

### Rule 3 — When you *can* read a rate column directly

You're not aggregating across rows. Specifically:

- **Exact-grain lookup** — every grain column pinned by a `WHERE`, returning one row.
- **Time series at natural grain** — plotting one row per period, no collapse.
- **Filter / sort / window** — keeping row identity (`ORDER BY arpdau LIMIT 10`).

Mental test: *does my SELECT produce one row per stored row, or fewer?* Fewer ⇒ recompute.

### Rule 4 — Don't aggregate `engagement_daily` measures across breakdowns blindly

`dau`, `new_users`, `payers`, `sessions` are upper bounds when summed across
country/platform (Unity returns one row per breakdown). For single-cell filters
they're correct. To roll up, prefer recomputing from the source with a coarser
groupBy in the ingestion layer.

---

## 5. Recipe book

### A. Daily ROAS by country (last 14d, US/iOS)

```sql
SELECT
  date,
  SUM(spend)                                              AS spend,
  SUM(cohort_revenue)                                     AS revenue,
  SAFE_DIVIDE(SUM(cohort_revenue), NULLIF(SUM(spend), 0)) AS roas
FROM `chef-master-8f916.dbt_tri_marts.ua_performance_daily`
WHERE country  = 'US'
  AND platform = 'ios'
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
GROUP BY date
ORDER BY date;
```

### B. Top-10 campaigns by spend with attached ARPDAU

```sql
SELECT
  network,
  campaign,
  SUM(spend)                                          AS spend,
  SUM(installs)                                       AS installs,
  SAFE_DIVIDE(SUM(spend), NULLIF(SUM(installs), 0))   AS ecpi,
  SAFE_DIVIDE(SUM(revenue), NULLIF(SUM(daus), 0))     AS arpdau,
  SAFE_DIVIDE(SUM(cohort_revenue), NULLIF(SUM(spend), 0)) AS roas
FROM `chef-master-8f916.dbt_tri_marts.ua_performance_daily`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY network, campaign
ORDER BY spend DESC
LIMIT 10;
```

### C. Retention trend (game-wide)

```sql
SELECT
  date,
  -- recompute, since rolling up across countries/platforms
  SAFE_DIVIDE(SUM(d1_retention  * dau), NULLIF(SUM(dau), 0)) AS d1_retention,
  SAFE_DIVIDE(SUM(d7_retention  * dau), NULLIF(SUM(dau), 0)) AS d7_retention,
  SAFE_DIVIDE(SUM(d30_retention * dau), NULLIF(SUM(dau), 0)) AS d30_retention
FROM `chef-master-8f916.dbt_tri_marts.engagement_daily`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date;
```

### D. UA acquisition funnel (one campaign, last 7d)

```sql
SELECT
  SUM(impressions)                                                 AS impressions,
  SUM(clicks)                                                      AS clicks,
  SUM(installs)                                                    AS installs,
  SUM(revenue_events)                                              AS purchases,
  SAFE_DIVIDE(SUM(clicks), NULLIF(SUM(impressions), 0))            AS impr_to_click,
  SAFE_DIVIDE(SUM(installs), NULLIF(SUM(clicks), 0))               AS click_to_install,
  SAFE_DIVIDE(SUM(revenue_events), NULLIF(SUM(installs), 0))       AS install_to_purchase
FROM `chef-master-8f916.dbt_tri_marts.ua_funnel_daily`
WHERE campaign = 'YOUR_CAMPAIGN_NAME'
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
```

### E. Cohort retention curve (d1/d3/d7/d14/d30, US, segment by app_version)

Uses the analytics layer (not a mart):

```sql
SELECT
  cohort_date,
  app_version,
  SUM(cohort_size)                                                          AS cohort_size,
  SAFE_DIVIDE(SUM(retained_d1_users),  NULLIF(SUM(cohort_size), 0))         AS d1_retention,
  SAFE_DIVIDE(SUM(retained_d3_users),  NULLIF(SUM(cohort_size), 0))         AS d3_retention,
  SAFE_DIVIDE(SUM(retained_d7_users),  NULLIF(SUM(cohort_size), 0))         AS d7_retention,
  SAFE_DIVIDE(SUM(retained_d14_users), NULLIF(SUM(cohort_size), 0))         AS d14_retention,
  SAFE_DIVIDE(SUM(retained_d30_users), NULLIF(SUM(cohort_size), 0))         AS d30_retention
FROM `chef-master-8f916.analytics.retention_cohorts`
WHERE geo_country = 'US'
GROUP BY cohort_date, app_version
ORDER BY cohort_date, app_version;
```

### F. Cohort LTV curve (D7/D14/D30, US, segment by app_version)

```sql
SELECT
  cohort_date,
  app_version,
  ANY_VALUE(cohort_size)                                                                  AS cohort_size,
  SAFE_DIVIDE(SUM(IF(days_since_install <= 7,  iap_revenue, 0)), ANY_VALUE(cohort_size))  AS ltv_d7,
  SAFE_DIVIDE(SUM(IF(days_since_install <= 14, iap_revenue, 0)), ANY_VALUE(cohort_size))  AS ltv_d14,
  SAFE_DIVIDE(SUM(IF(days_since_install <= 30, iap_revenue, 0)), ANY_VALUE(cohort_size))  AS ltv_d30
FROM `chef-master-8f916.dbt_tri_marts.cohort_ltv_daily`
WHERE geo_country = 'United States'
GROUP BY cohort_date, app_version
ORDER BY cohort_date, app_version;
```

### G. Creative leaderboard (best video completion, min 1k plays)

```sql
SELECT
  ad_name,
  SUM(spend)                                                   AS spend,
  SUM(video_plays)                                             AS plays,
  SUM(video_p100)                                              AS completed,
  SAFE_DIVIDE(SUM(video_p100), NULLIF(SUM(video_plays), 0))    AS completion_rate,
  SAFE_DIVIDE(SUM(installs), NULLIF(SUM(clicks), 0))           AS cvr,
  SAFE_DIVIDE(SUM(spend), NULLIF(SUM(installs), 0))            AS ecpi
FROM `chef-master-8f916.dbt_tri_marts.creative_performance_daily`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
GROUP BY ad_name
HAVING plays >= 1000
ORDER BY completion_rate DESC
LIMIT 20;
```

---

## 6. Caveats summary

| Issue | Where | Mitigation |
|---|---|---|
| Adjust attribution mutates retroactively | all Adjust marts | 14d incremental window absorbs typical lag; `--full-refresh` for older corrections |
| Unity DAU double-counts across `clientVersion` | `engagement_daily` | re-pull `unity_data_gateway` w/o clientVersion in groupBy; or rely on rates only |
| Cohort LTV is IAP-only | `cohort_ltv_daily` | Firebase ad events have no $ value, so the mart covers IAP revenue only. For IAP+ad cohort LTV / d28 ROAS, ingest the Adjust Cohorts API (upstream `zero1-data` change) |
| Firebase `acquisition_source` ≠ Adjust attribution | `analytics.retention_cohorts` | These are two attribution views. For UA campaign performance use `ua_performance_daily` (Adjust); use `analytics.retention_cohorts.acquisition_source` only as a coarse Firebase-side label |
| Meta `purchase_roas` ≠ Adjust `roas` | `creative_performance_daily` vs `ua_performance_daily` | Treat Adjust as truth for spend/ROAS reporting; Meta for relative creative comparison |
| In-game progression funnels not in this layer | n/a | Use `models/staging/firebase/stg_events` + analytics layer |
| `acquisitionChannel` always `'None'` from Unity | `engagement_daily` | Unity Analytics doesn't carry channel attribution — don't try to join it to UA performance |

---

## 7. Running

```bash
# Full first build (creates tables, no incremental filter)
dbt build --select +marts

# Daily refresh (last 14d for most marts; last 44d for cohort_ltv_daily)
dbt build --select +marts

# Force a full rebuild after a backfill or logic change
dbt build --select +marts --full-refresh

# Just one mart and its upstreams
dbt build --select +ua_performance_daily

# Just the staging layer
dbt build --select staging.adjust staging.meta_ads staging.unity
```

Marts schema in BigQuery: `chef-master-8f916.<dataset>_marts` where `<dataset>`
comes from your `profiles.yml` target (e.g., `dbt_tri` → `dbt_tri_marts`).

---

## 8. Extending

- **New metric from existing source**: add column to the staging view, then to
  the mart. Schema-evolves cleanly thanks to `on_schema_change='append_new_columns'`
  on every mart.
- **New ad network**: add raw table via `zero1-data` config, add a `stg_<src>__*`
  view, then either add to an existing mart (preferred — keeps the
  source-of-truth pattern) or create a new dedicated mart.
- **Tests**: see `marts.yml`. Currently `not_null` on date keys; add `unique`
  tests on `(date, ...grain)` keys when the data is dense enough to be reliable.

# 🎮 Zero-One Games — Mobile Game Analytics Platform

An end-to-end analytics solution for the mobile game **Chef Master**, built on
**dbt + BigQuery + a BI/Semantic layer**. It answers one quantifiable business
question:

> **Are we acquiring players profitably?** — measured by **D30 ROAS** and
> **LTV : CAC**.

It unifies four sources (Firebase/GA4 events, Adjust attribution, Meta Ads,
Unity Analytics) into governed, tested, dashboard-ready marts.

---

## 📌 The headline metric

```sql
-- D30 ROAS by acquisition network (last 14 days)
SELECT
  network,
  SUM(spend)                                              AS spend,
  SUM(cohort_revenue)                                     AS revenue,
  SAFE_DIVIDE(SUM(cohort_revenue), NULLIF(SUM(spend), 0)) AS roas
FROM marts.ua_performance_daily
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
GROUP BY network
ORDER BY spend DESC;
```

`ROAS ≥ 1` ⇒ the campaign pays back within the cohort window. See
[`docs/metrics_dictionary.md`](docs/metrics_dictionary.md) for every metric's
definition, SQL logic and business impact.

---

## 🏛️ Architecture (Medallion + Dimensional)

```
                 ┌──────────────────────── BRONZE (raw) ───────────────────────┐
 Firebase/GA4    Adjust            Meta Ads           Unity Analytics
 events_*        raw.adjust_report raw.meta_ads_*     raw.unity_*
      │               │                 │                   │
      ▼               ▼                 ▼                   ▼
                 ┌──────────────────── SILVER (staging) ───────────────────────┐
 stg_events*     stg_adjust__report stg_meta_ads__*    stg_unity__analytics_daily
 (typed, flattened, snake_cased, PII hashed, deduped — materialized as views)
      │
      ▼
                 ┌──────────────────── GOLD (marts) ───────────────────────────┐
 ua_performance_daily · engagement_daily · iap_arpdau_daily · cohort_ltv_daily
 creative_performance_daily · ua_funnel_daily · session_depth_daily
 tutorial_funnel_daily · overview_daily          (incremental tables / 1 view)
      │
      ▼
 analytics.*  (exploratory views)        Semantic Layer (MetricFlow)  →  BI dashboards (exposures)
```

| Layer | Schema | Materialization | Responsibility |
|---|---|---|---|
| **Bronze** | `raw` / GA4 export | source | Landed, untransformed data |
| **Silver** | `staging` | view | 1 model per source object; typing, snake_case, struct flattening, **PII hashing**, light dedup |
| **Gold** | `marts` | incremental table | Business-ready facts at a documented grain; tested; dashboard-facing |
| **Analytics** | `analytics` | view | Deeper/exploratory player-behaviour models |

Full diagram + ERD: [`docs/architecture.md`](docs/architecture.md).
Mart reference + recipe book: [`models/marts/README.md`](models/marts/README.md).
Event table reference: [`STG_EVENTS.md`](STG_EVENTS.md).

---

## 🗂️ Repo map

```
models/
  staging/        firebase · adjust · meta_ads · unity  (sources + stg_* views)
  marts/          9 business marts + marts.yml (tests, docs, unit tests)
  analytics/      player-behaviour views + analytics.yml
  semantic/       MetricFlow semantic model + metrics (ROAS, eCPI, ARPDAU…)
  exposures.yml   BI dashboards that consume the marts
macros/           ga4_flatten_event_columns · iap · mask_pii · meta_get_action
tests/            singular data tests (reconciliation, future-date, sign checks)
docs/             architecture · metrics_dictionary · data_governance · demo_plan · slides/
.github/          CI/CD workflows, PR template, CODEOWNERS
```

---

## ✅ The 5 evaluation pillars — where the evidence lives

| Pillar | Evidence |
|---|---|
| **1 · Modeling & Architecture** | Medallion layers + dimensional marts · [`docs/architecture.md`](docs/architecture.md) (ERD/DAG) · `on_schema_change`, partition/cluster configs |
| **2 · Transformation** | 6 incremental marts (`insert_overwrite`) + incremental staging · macros (`ga4_flatten_event_columns`, `iap`, `meta_get_action`) · window-function dedup in `stg_events` · `dbt_utils` |
| **3 · Governance (Quality & Security)** | Generic + singular + **unit** tests · grain-uniqueness · source freshness · **salted SHA-256 PII hashing** · policy-tag/masking + grants design · secrets via `env_var` · [`docs/data_governance.md`](docs/data_governance.md) |
| **4 · Data Insight** | MetricFlow **Semantic Layer** (`models/semantic/`) · BI **exposures** · [`docs/metrics_dictionary.md`](docs/metrics_dictionary.md) |
| **5 · DataOps** | GitHub Actions **CI/CD** (`.github/workflows/`) · sqlfluff + pre-commit · branching/release flow · [`docs/dataops.md`](docs/dataops.md) |

Interview walkthrough: [`docs/demo_plan.md`](docs/demo_plan.md) ·
Slides (PowerPoint): [`docs/slides/Zero-One-Games-AE-TPF.pptx`](docs/slides/Zero-One-Games-AE-TPF.pptx)
(regenerate with `python scripts/build_deck.py`).

---

## 🚀 Quickstart

```bash
# 0. Prereqs: Python 3.10+, dbt-bigquery, a BigQuery service account.
pip install dbt-bigquery

# 1. Configure secrets via environment (never commit them) — see profiles.yml.example
#    PowerShell:
$env:DBT_GOOGLE_KEYFILE = "C:\path\to\key.json"
$env:DBT_PII_SALT       = "a-long-random-string"

# 2. Install packages
dbt deps

# 3. Sanity-check the project parses
dbt parse

# 4. First full build (creates tables, runs all tests)
dbt build --full-refresh

# 5. Day-to-day incremental refresh (last 14–44d windows)
dbt build

# 6. Docs site (lineage, ERD, descriptions persisted to BigQuery)
dbt docs generate && dbt docs serve
```

Selectors:

```bash
dbt build -s +ua_performance_daily   # one mart and everything it needs
dbt build -s staging                 # just the silver layer
dbt test  -s marts                   # just the gold-layer tests
dbt source freshness                 # raw-data SLA check
```

---

## 🔐 Security note

No secrets live in this repo. Connection details and the PII salt are read from
environment variables (`profiles.yml` → `env_var(...)`); `*.json`/`*.bkp`/`.env*`
are git-ignored. PII (`user_id`) is salted-SHA-256 hashed in the staging layer.
Details: [`docs/data_governance.md`](docs/data_governance.md).

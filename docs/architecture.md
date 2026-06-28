# Architecture & Data Modeling

## 1. Modeling approach

- **Medallion layering** (Bronze → Silver → Gold) for clear, testable
  separation of concerns.
- **Dimensional (Kimball) marts** at the Gold layer: each mart is a **fact** at
  a documented daily grain, described by a small set of **conformed
  dimensions** (`date`, `app`, `platform`, `country/geo`, `network/campaign`,
  `app_version`, `spender_segment`). Conformed dimensions are what let analysts
  slice ROAS, ARPDAU and LTV the same way across every mart.
- **Long (tidy) facts** over wide pivots where a dimension would otherwise
  explode into columns (e.g. `spender_segment`, `step_num`, `days_since_install`
  are rows, not columns) — so new checkpoints/segments need no schema change.

## 2. Layer responsibilities

| Layer | Schema | Materialization | Rules |
|---|---|---|---|
| Bronze (raw) | `raw`, GA4 export | source | No transformation. Declared in `src_*.yml` with freshness SLAs. |
| Silver (staging) | `staging` | **view** | One model per source object. Type-cast, snake_case, flatten structs, hash PII, light dedup. No business logic, no joins across sources. |
| Gold (marts) | `marts` | **incremental table** | Business facts at a stated grain. Tested for grain-uniqueness + ranges. The only layer BI should touch. |
| Analytics | `analytics` | view | Deeper player-behaviour exploration; reuses `stg_events`. |

**Why these materializations:** staging views are free and always fresh; marts
are incremental tables (`insert_overwrite`, partitioned by date) because they
back dashboards and Adjust/Firebase data mutates retroactively — a 14–44 day
rebuild window absorbs late-arriving data idempotently.

## 3. Source → mart lineage (DAG)

```mermaid
flowchart LR
  subgraph Bronze[Bronze · raw]
    GA4[(Firebase events_*)]
    ADJ[(raw.adjust_report)]
    META[(raw.meta_ads_*)]
    UNITY[(raw.unity_*)]
  end

  subgraph Silver[Silver · staging views]
    SE_D[stg_events_daily]
    SE_I[stg_events_intraday]
    SE[stg_events]
    SADJ[stg_adjust__report]
    SMETA[stg_meta_ads__ad_daily]
    SUNITY[stg_unity__analytics_daily]
  end

  subgraph Gold[Gold · marts]
    UAP[ua_performance_daily]
    UAF[ua_funnel_daily]
    ENG[engagement_daily]
    CRE[creative_performance_daily]
    IAP[iap_arpdau_daily]
    LTV[cohort_ltv_daily]
    SESS[session_depth_daily]
    TUT[tutorial_funnel_daily]
    OVW[overview_daily]
  end

  subgraph Consume[Semantic Layer + BI]
    SL[[MetricFlow metrics]]
    BI[[BI dashboards / exposures]]
  end

  GA4 --> SE_D --> SE
  GA4 --> SE_I --> SE
  ADJ --> SADJ --> UAP
  SADJ --> UAF
  META --> SMETA --> CRE
  UNITY --> SUNITY --> ENG
  SE --> IAP
  SE --> LTV
  SE --> SESS
  SE --> TUT
  UAP --> OVW
  ENG --> OVW

  UAP --> SL --> BI
  OVW --> BI
  LTV --> BI
  CRE --> BI
```

## 4. Conformed-dimension ERD (Gold layer)

A star-schema view of the marts: fact tables (daily grain) surrounded by the
conformed dimensions that join/slice them.

```mermaid
erDiagram
  DIM_DATE ||--o{ UA_PERFORMANCE_DAILY : date
  DIM_DATE ||--o{ ENGAGEMENT_DAILY : date
  DIM_DATE ||--o{ IAP_ARPDAU_DAILY : date
  DIM_DATE ||--o{ COHORT_LTV_DAILY : cohort_date
  DIM_APP ||--o{ UA_PERFORMANCE_DAILY : app
  DIM_GEO ||--o{ UA_PERFORMANCE_DAILY : country
  DIM_GEO ||--o{ IAP_ARPDAU_DAILY : geo_country
  DIM_GEO ||--o{ COHORT_LTV_DAILY : geo_country
  DIM_CHANNEL ||--o{ UA_PERFORMANCE_DAILY : network
  DIM_APP_VERSION ||--o{ IAP_ARPDAU_DAILY : app_version
  DIM_APP_VERSION ||--o{ COHORT_LTV_DAILY : app_version
  DIM_SPENDER ||--o{ IAP_ARPDAU_DAILY : spender_segment

  UA_PERFORMANCE_DAILY {
    date date PK
    string app PK
    string platform PK
    string country PK
    string network PK
    string campaign PK
    int spend
    int cohort_revenue
    int installs
    float roas
  }
  ENGAGEMENT_DAILY {
    date date PK
    string country PK
    string platform PK
    int dau
    float arpdau
    float d30_retention
  }
  IAP_ARPDAU_DAILY {
    date date PK
    string geo_country PK
    string app_version PK
    string spender_segment PK
    int dau
    float iap_revenue
    float arpdau_iap
  }
  COHORT_LTV_DAILY {
    date cohort_date PK
    int days_since_install PK
    string geo_country PK
    string app_version PK
    int cohort_size
    float iap_revenue
  }
```

## 5. Source-of-truth precedence

Three systems measure overlapping things at different scopes — by design they
do **not** reconcile, and dashboards label them distinctly:

| Question | Source of truth | Mart |
|---|---|---|
| How did *this UA campaign* perform? | **Adjust** | `ua_performance_daily`, `ua_funnel_daily` |
| How is *the whole game* doing? | **Unity Analytics** | `engagement_daily` |
| How is *this creative* performing? | **Meta Ads** | `creative_performance_daily` |
| In-game behaviour, cohorts, LTV | **Firebase events** | `iap_arpdau_daily`, `cohort_ltv_daily`, session/tutorial marts |

## 6. Extensibility

- New metric from an existing source → add a column to the staging view, then
  the mart. `on_schema_change='append_new_columns'` evolves marts cleanly.
- New source → add `raw` table + `src_*.yml`, a `stg_<src>__*` view, then fold
  into an existing mart (preferred) or a new one.
- New LTV checkpoint (D45/D60) → bump `max_dsi` and `--full-refresh`; no schema
  change (long format).

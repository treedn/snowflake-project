# Data Governance — Quality & Security

This project treats governance as two halves of one pillar: **can I trust the
numbers (quality)** and **is the data protected (security)**. Both are enforced
in code so they run on every build, not in a runbook.

---

## 1. Data Quality

### 1.1 Where the checks live

| Layer | What we assert | How |
|---|---|---|
| Sources | freshness (raw tables are arriving) | `dbt source freshness` (see `src_adjust.yml`) |
| Staging | typed columns, `not_null` on keys, `accepted_values` on enums, conditional `not_null` (e.g. `price_gems` only on `iap_purchase`) | generic tests in `stg_events.yml` |
| Marts | **grain uniqueness**, non-null keys, bounded ranges for rates, reconciliation across marts | generic + singular tests in `marts.yml` and `tests/` |
| Logic | golden-record behaviour of `overview_daily` | dbt **unit tests** in `marts.yml` |

### 1.2 Test taxonomy used here

- **Generic tests** — `not_null`, `unique`, `accepted_values`, plus
  `dbt_utils.unique_combination_of_columns` (grain integrity) and
  `dbt_utils.accepted_range` (bounded metrics like `0 <= retention <= 1`).
- **Singular tests** (`tests/*.sql`) — bespoke business rules:
  - `assert_marts_no_future_dates.sql` — no mart row is dated in the future.
  - `assert_no_negative_revenue.sql` — spend / revenue / IAP value are
    physically non-negative.
  - `assert_cohort_ltv_curve_elapsed.sql` — a `(cohort_date, dsi)` LTV point is
    only emitted once that calendar day has fully elapsed (no partial days).
  - `assert_iap_arpdau_internally_consistent.sql` — the stored `arpdau_iap` rate
    always equals `iap_revenue / dau` (guards against refactors changing one
    expression but not the other).
- **Unit tests** — `test_overview_daily_*` mock UA + engagement inputs and
  assert the exact joined/derived output (ECPI, ROAS, ARPDAU, ARPPU). These run
  with no warehouse data and catch logic regressions in CI.

### 1.3 Severity strategy

Hard invariants (grain uniqueness, not-null keys, future dates) are
`error` — they fail the build. Data-shape expectations that can legitimately
wobble with real data (e.g. range bounds on noisy ratios) are `warn`, so they
surface in CI without blocking a deploy. This keeps `dbt build` green while
still flagging drift.

### 1.4 The reconciliation principle

Every monetary number flows from a **single definition** — `iap_value_usd()` in
`macros/iap.sql`. Because `iap_arpdau_daily`, `cohort_ltv_daily` and
`analytics.retention_cohorts` all call it, a singular test can assert they
reconcile. This is how we caught and fixed the historic
`retention_cohorts.total_iap_value_usd` bug (it summed the generic `amount` coin
param across all events and inflated revenue by orders of magnitude).

---

## 2. Data Security

Defence in depth: **mask in the pipeline** *and* **control access in the
warehouse**.

### 2.1 PII inventory

| Column | Sensitivity | Control |
|---|---|---|
| `user_id` | Direct identifier (account) | **Salted SHA-256 in staging** — raw value never persisted |
| `user_pseudo_id` | Pseudonymous device id (needed for joins) | Policy tag + authorized views in prod |
| `geo_city`, `device_mobile_model_name` | Quasi-identifiers | Policy tag (masked for non-privileged roles) |

Columns are flagged in `stg_events.yml` with `meta.contains_pii: true` and a
`masking_policy`, so the inventory is queryable from `manifest.json` and shown in
`dbt docs`.

### 2.2 In-pipeline pseudonymisation (`macros/mask_pii.sql`)

`hash_pii(col)` emits a **salted, deterministic** SHA-256:

```sql
to_hex(sha256(concat(cast(user_id as string), '<DBT_PII_SALT>')))
```

- **Salted** — the salt comes from `env_var('DBT_PII_SALT')` (secret manager /
  CI secret), defeating public rainbow tables.
- **Deterministic** — identical inputs hash identically, so joins on the hash
  still work and analytics is unaffected.
- **NULL-safe** — NULLs stay NULL.

Applied once, in `ga4_flatten_event_columns()`, so both the daily and intraday
shards are masked consistently.

### 2.3 Warehouse-native controls (BigQuery)

The in-pipeline hash is one layer. In production we also apply:

1. **Column-level security with policy tags + dynamic data masking.** Tag PII
   columns (`user_pseudo_id`, `geo_city`, …) with a Data Catalog policy tag;
   attach a masking rule (`SHA256` / `DEFAULT_MASKING_VALUE`). Non-privileged
   roles transparently see masked values; no query rewrite needed.
2. **Authorized views.** Analysts get access to the `marts` / `analytics`
   datasets only. Those datasets are *authorized* to read `staging`, so raw PII
   is never directly grantable to analysts.
3. **Dataset IAM + dbt `grants`.** Read access is provisioned as code via dbt's
   `+grants` config (see `dbt_project.yml`) so permissions are versioned and
   reviewed in PRs rather than clicked in a console.
4. **Row-level security** (optional) — e.g. a regional access policy on
   `geo_country` for teams that may only see their market.

### 2.4 Secrets management

- No secrets in the repo. `profiles.yml` reads everything from `env_var()`
  (`DBT_GOOGLE_KEYFILE`, `DBT_BIGQUERY_PROJECT`, `DBT_PII_SALT`). See
  `profiles.yml.example`.
- `*.json`, `*.bkp`, `.env*` are git-ignored.
- CI authenticates to GCP via **Workload Identity Federation (OIDC)** — no
  long-lived JSON key exists in the pipeline.
- Demo hygiene (per interview brief): credentials are env-injected, so screen
  sharing never exposes a key.

# Interview Demo Plan (≈90 min)

Structure mirrors the TPF brief: 5 min intro · 75 min (15 per pillar) · 10 min
Q&A. For each pillar: **Show** (where it lives) → **Why** (the decision) →
**What-if** (a live extension you're ready for).

> One-liner: *"An end-to-end dbt + BigQuery platform that tells Zero-One Games
> whether they acquire players profitably — headline metric D30 ROAS / LTV:CAC —
> unifying Firebase, Adjust, Meta and Unity."*

---

## 0 · Intro (5 min)
- Business problem + the single quantifiable metric (D30 ROAS / LTV:CAC).
- 30-second tour of the repo map (README) and the medallion diagram
  (`docs/architecture.md`).

## 1 · Data Modeling & Architecture (15 min)
- **Show:** `docs/architecture.md` DAG + ERD; the `staging → marts → analytics`
  layout; one mart (`ua_performance_daily`) and its grain.
- **Why:** medallion for separation; dimensional/conformed dims for consistent
  slicing; long-format facts (spender_segment, days_since_install) so new
  segments/checkpoints need no schema change; views for staging vs incremental
  tables for marts.
- **What-if:** "Add a `placement` dimension" → show it's a staging column + mart
  group-by, `on_schema_change='append_new_columns'` handles it.

## 2 · Data Transformation (15 min)
- **Show:** run `dbt build -s +iap_arpdau_daily`. Open `stg_events.sql`
  (window-function level attribution + run-based dedup), the incremental marts
  (`insert_overwrite`, 14/44-day windows), and the macros:
  `ga4_flatten_event_columns` (DRYs ~120 lines across daily/intraday),
  `iap.sql` (single revenue definition), `meta_get_action`.
- **Why:** incremental + insert_overwrite for idempotent, cheap retroactive
  rebuilds (Adjust/Firebase mutate late); macros for one source of truth.
- **What-if:** "Add D45 to LTV" → bump `max_dsi`, `--full-refresh`. "New ad
  network" → new `stg_*` view feeding `ua_performance_daily`.

## 3 · Data Governance — Quality & Security (15 min)
- **Show (quality):** `dbt build` running tests — grain `unique_combination`,
  ranges, `accepted_values`, **singular** tests (`tests/`), and **unit tests**
  (`marts.yml`) that run with no warehouse data. `dbt source freshness`.
- **Show (security):** `macros/mask_pii.sql` salted SHA-256 on `user_id`;
  `meta.contains_pii` tags; `docs/data_governance.md` (policy tags / masking /
  authorized views / grants-as-code); secrets via `env_var`.
- **Why:** defense-in-depth (mask in pipeline + control in warehouse); severity
  strategy (hard invariants error, noisy ranges warn) keeps builds green while
  flagging drift.
- **What-if:** "Hash `user_pseudo_id` too" → wrap in `hash_pii()` (note: must
  hash consistently so joins survive). "Add a test that revenue never drops >50%
  d/d" → write a singular test live.

## 4 · Data Insight (15 min)
- **Show:** `docs/metrics_dictionary.md`; the MetricFlow Semantic Layer
  (`models/semantic/`) — `dbt sl query --metrics roas,ecpi --group-by network`;
  the BI exposures (`models/exposures.yml`) and the headline ROAS query.
- **Why:** metrics defined once (numerator/denominator) so every tool agrees and
  nobody `AVG()`s a rate; exposures wire warehouse → BI into the DAG.
- **What-if:** "Add ROI as a metric" → add a derived/ratio metric live. "ARPPU
  by app_version" → new ratio metric.

## 5 · DataOps (15 min)
- **Show:** `.github/workflows/ci.yml` (deps → parse → sqlfluff → build into an
  isolated CI dataset → tests on PR) and `cd.yml` (deploy to prod on merge);
  branching/release flow in `docs/dataops.md`; `.sqlfluff`, pre-commit, PR
  template, CODEOWNERS.
- **Why:** trunk-based + PR gates; CI builds into a throwaway dataset so prod is
  never touched by a PR; OIDC keyless auth.
- **What-if:** "Add a Slim CI (state:modified+)" → show the `--select state:modified+`
  selector and `--defer` against prod manifest.

## Q&A (10 min)
Have ready: the known caveats table (marts README §6), why Adjust/Unity/Meta
don't reconcile, and the `retention_cohorts` IAP-inflation bug you found & fixed.

---

### Pre-demo checklist
- [ ] `DBT_GOOGLE_KEYFILE` + `DBT_PII_SALT` set; `dbt debug` green.
- [ ] `dbt deps && dbt parse` clean.
- [ ] `dbt build` recently run; `dbt docs serve` open.
- [ ] Slides open: `docs/slides/Zero-One-Games-AE-TPF.pptx`.
- [ ] No secrets visible on screen.

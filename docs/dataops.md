# DataOps — Code Quality, Branching & Deployment

How changes get from a laptop to production safely.

## 1. Environments

| Env | Target | Dataset | Who/when |
|---|---|---|---|
| **Dev** | `dev` | `dbt_<developer>` | Local work; isolated per person |
| **CI** | `ci` | `dbt_ci_pr_<n>` (throwaway) | Every PR; dropped after the run |
| **Prod** | `prod` | `analytics` | On merge to `main` (gated) |

All three are the *same* code with different `env_var`-driven datasets — no
hard-coded connection details, no secrets in the repo (`profiles.yml`).

## 2. Branching strategy (trunk-based)

```
main  ───●───────────●───────────●────────▶   (always deployable; protected)
          \         /             \
feature   ●──●──●──●  (PR + CI)     ●──●  (PR + CI)
```

- Short-lived `feature/*` and `fix/*` branches off `main`.
- `main` is **protected**: no direct pushes; PR + green CI + 1 review (CODEOWNERS)
  required to merge.
- Squash-merge to keep `main` history linear and each change atomic/revertable.

## 3. Code quality gates

| Gate | Tool | When |
|---|---|---|
| Formatting / style | **sqlfluff** (BigQuery + dbt templater) | pre-commit + CI |
| Secrets / large files | **pre-commit** (`detect-private-key`, …) | pre-commit |
| Docs & test coverage | **dbt-checkpoint** (marts must have description + ≥1 test) | pre-commit |
| Parse / refs | `dbt parse` | CI |
| Data correctness | `dbt build` (models + generic + singular + unit tests) | CI on isolated dataset |

## 4. CI pipeline (`.github/workflows/ci.yml`)

On each PR:
1. **Auth** to GCP via **Workload Identity Federation (OIDC)** — keyless, no JSON
   key ever stored.
2. `dbt deps` → `dbt parse` (fast fail on broken refs).
3. **sqlfluff** lints only the SQL changed in the PR.
4. **Slim CI:** `dbt build --select state:modified+ --defer --state ./prod-manifest`
   builds only changed models + descendants into the throwaway PR dataset,
   deferring unchanged refs to prod. Runs all their tests.
5. The PR dataset is **dropped** in an `always()` step.

This means a PR is validated against real BigQuery without ever touching prod,
and only pays to build what changed.

## 5. CD / release (`.github/workflows/cd.yml`)

On merge to `main`:
1. `dbt source freshness` (non-blocking alert).
2. `dbt build --target prod` (gated by a GitHub `production` environment with
   required approval).
3. Upload `manifest.json` as an artifact so the next PR's Slim CI can defer to it.
4. `dbt docs generate` for the catalog.

**Versioned releases:** tag `main` (`vX.Y.Z`); the tag is the immutable record of
what's in prod. Roll back = redeploy the previous tag.

## 6. Orchestration (scheduled runs)

The marts have explicit cadences (see model headers / `STG_EVENTS.md`):
- `stg_events_intraday`: every ~15 min.
- `stg_events_daily` + marts: daily after 06:00 UTC (`dbt build -s +marts`).
- `cohort_ltv_daily`: 44-day window; the rest 14-day.

Run via dbt Cloud jobs, Cloud Composer/Airflow, or a scheduled GitHub Action —
the same `dbt build` commands the CD job uses.

# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **dbt project** (`zero_one_games`) that transforms mobile-game marketing/telemetry
data in **Google BigQuery** (project `chef-master-8f916`, location `EU`). There is no web app or
long-running server; "running" the project means invoking the `dbt` CLI. See `README.md`,
`dbt_project.yml`, and `STG_EVENTS.md` for project details.

### Toolchain
- `dbt-bigquery` (dbt Core) is installed into a Python venv at `.venv/` (the startup/update script
  creates it and runs `dbt deps`). Activate it first: `source .venv/bin/activate`.
- `dbt` reads `profiles.yml` from the repo root automatically (no `--profiles-dir` flag needed).

### Credentials (required for anything that touches the warehouse)
- BigQuery auth uses a **service-account JSON key**. `profiles.yml` reads its path from the
  `DBT_BIGQUERY_KEYFILE` env var (default `/workspace/.secrets/bigquery-keyfile.json`).
- If the key is provided as a secret (JSON string), write it to that path and/or set
  `DBT_BIGQUERY_KEYFILE` before running warehouse commands, e.g.:
  `mkdir -p .secrets && printf '%s' "$GCP_SERVICE_ACCOUNT_JSON" > .secrets/bigquery-keyfile.json`
- Raw source data is produced by a **separate external pipeline (`zero1-data`, not in this repo)**
  and lives in BigQuery `raw.*` / `analytics_*` schemas. Models only read it; without that data a
  full `dbt build` cannot produce real results even with valid credentials.

### What works offline (no credentials) — use these to validate changes
- `dbt deps` — install package dependencies (`packages.yml`).
- `dbt parse` — validate the whole project (Jinja, refs, sources, config). This is the lint/validate step.
- `dbt list` — resolve and print the model DAG.

### What needs credentials + warehouse access
- `dbt debug` (connection test), `dbt compile`, `dbt run`, `dbt build`, `dbt test`. All of these
  open a BigQuery connection during graph compilation, so they fail fast without a valid keyfile.

### Gotchas
- `dbt_project.yml` pins GA4 wildcard proxy suffixes (`ga4_daily_schema_proxy_suffix`,
  `ga4_intraday_schema_proxy_suffix`) to specific `events_YYYYMMDD` table dates. These must match
  tables that actually exist in BigQuery, otherwise Firebase staging models fail.
- `dbt deps` rewrites `package-lock.yml`; the committed lockfile is already in the format the
  installed dbt produces, so re-running `dbt deps` leaves the working tree clean.
- `dbt docs serve` (optional) serves docs on port `8080`; nothing else listens on a port.

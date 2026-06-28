# Summary

<!-- What does this PR change and why? Link the issue/ticket. -->

## Type of change
- [ ] New model / metric
- [ ] Bug fix (data correctness)
- [ ] Refactor (no output change)
- [ ] Tests / docs only
- [ ] DataOps / CI

## Checklist
- [ ] `dbt parse` passes locally
- [ ] `dbt build -s state:modified+` runs green (models + tests)
- [ ] New/changed models have a description and grain documented in a `.yml`
- [ ] New/changed marts have a grain-uniqueness test
- [ ] sqlfluff passes on changed SQL
- [ ] No secrets committed; PII columns flagged `meta.contains_pii`
- [ ] Updated `docs/` (metrics dictionary / README) if metrics or grain changed

## Data impact
<!-- Does this change historical numbers? Backfill / --full-refresh needed? -->

## How to verify
<!-- Queries / screenshots / row counts reviewers can run. -->

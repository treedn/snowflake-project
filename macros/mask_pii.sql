{#
  PII handling macros (defense-in-depth, dbt side).

  These complement the warehouse-native controls documented in
  docs/data_governance.md (BigQuery policy tags / dynamic data masking,
  authorized views, dataset IAM). They give us deterministic, in-pipeline
  pseudonymisation so that anyone with table access still never sees a raw
  identifier — while joins on the hashed value keep working.
#}

{#
  hash_pii: deterministic, salted SHA-256 of a sensitive column.

  - Salted with env_var('DBT_PII_SALT') so the digest can't be reversed with a
    public rainbow table. The salt lives in the environment / secret manager,
    never in the repo.
  - Deterministic: the same input always maps to the same hash, so hashed keys
    are still join-safe across models.
  - NULL-safe: NULLs stay NULL (we don't hash a literal 'null').
#}
{% macro hash_pii(column_name) -%}
    case
        when {{ column_name }} is null then null
        else to_hex(sha256(concat(cast({{ column_name }} as string), '{{ pii_salt() }}')))
    end
{%- endmacro %}

{#
  pii_salt: resolve the hashing salt from the environment.
  Falls back to a clearly-marked non-production default so local dev still runs;
  CI/prod must inject DBT_PII_SALT (see .github/workflows + docs/data_governance.md).
#}
{% macro pii_salt() -%}
    {{ env_var('DBT_PII_SALT', 'LOCAL_DEV_SALT_DO_NOT_USE_IN_PROD') }}
{%- endmacro %}

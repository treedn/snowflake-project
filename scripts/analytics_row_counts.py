"""List analytics schema tables and 7-day row counts via BigQuery."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PROJECT = os.environ.get("DBT_BIGQUERY_PROJECT", "chef-master-8f916")
DATASET = os.environ.get("ANALYTICS_DATASET", "analytics")
# Credentials come from the environment, never hard-coded. Set DBT_GOOGLE_KEYFILE
# (or GOOGLE_APPLICATION_CREDENTIALS) to a service-account key path, or rely on
# Application Default Credentials (`gcloud auth application-default login`).
KEYFILE_ENV = os.environ.get("DBT_GOOGLE_KEYFILE") or os.environ.get(
    "GOOGLE_APPLICATION_CREDENTIALS"
)
OUT = Path(__file__).resolve().parent / "analytics_row_counts_result.json"


def run_bq_query(sql: str) -> list[dict]:
    env = os.environ.copy()
    if KEYFILE_ENV:
        env["GOOGLE_APPLICATION_CREDENTIALS"] = KEYFILE_ENV
    cmd = [
        "bq",
        "query",
        "--use_legacy_sql=false",
        f"--project_id={PROJECT}",
        "--format=json",
        "--max_rows=10000",
        sql,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    if not proc.stdout.strip():
        return []
    return json.loads(proc.stdout)


def main() -> int:
    tables_sql = f"""
    SELECT table_name
    FROM `{PROJECT}.{DATASET}.INFORMATION_SCHEMA.TABLES`
    WHERE table_type = 'BASE TABLE'
    ORDER BY table_name
    """
    tables = [row["table_name"] for row in run_bq_query(tables_sql)]

    date_columns_sql = f"""
    SELECT table_name, column_name
    FROM `{PROJECT}.{DATASET}.INFORMATION_SCHEMA.COLUMNS`
    WHERE column_name IN ('date', 'event_date', 'cohort_date')
    ORDER BY table_name, column_name
    """
    date_cols = run_bq_query(date_columns_sql)
    date_by_table: dict[str, str] = {}
    for row in date_cols:
        table = row["table_name"]
        if table not in date_by_table:
            date_by_table[table] = row["column_name"]

    results = {"tables": tables, "row_counts_last_7_days": []}

    for table in tables:
        date_col = date_by_table.get(table)
        if not date_col:
            count_sql = f"""
            SELECT '{table}' AS table_name, CAST(NULL AS DATE) AS day, COUNT(*) AS row_count
            FROM `{PROJECT}.{DATASET}.{table}`
            """
            results["row_counts_last_7_days"].extend(run_bq_query(count_sql))
            continue

        count_sql = f"""
        SELECT
          '{table}' AS table_name,
          CAST({date_col} AS DATE) AS day,
          COUNT(*) AS row_count
        FROM `{PROJECT}.{DATASET}.{table}`
        WHERE CAST({date_col} AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY 1, 2
        ORDER BY 1, 2
        """
        results["row_counts_last_7_days"].extend(run_bq_query(count_sql))

    OUT.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(OUT)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise

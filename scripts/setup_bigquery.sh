#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
# shellcheck source=_load_env.sh
source "$(dirname "$0")/_load_env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> BigQuery setup for project: $PROJECT_ID"

# ── Tables ────────────────────────────────────────────────────────────────────
echo "--> Creating dataset + tables..."
sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$ROOT/bigquery/setup.sql" \
  | bq query --use_legacy_sql=false --project_id="$PROJECT_ID"

# ── Stored procedures ─────────────────────────────────────────────────────────
echo "--> Creating stored procedures..."
for f in "$ROOT"/bigquery/procedures/*.sql; do
  echo "    $f"
  sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$f" \
    | bq query --use_legacy_sql=false --project_id="$PROJECT_ID"
done

# ── Views ─────────────────────────────────────────────────────────────────────
echo "--> Creating views..."
for f in "$ROOT"/bigquery/views/*.sql; do
  echo "    $f"
  sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$f" \
    | bq query --use_legacy_sql=false --project_id="$PROJECT_ID"
done

echo "==> BigQuery setup complete."

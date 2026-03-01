#!/usr/bin/env bash
set -euo pipefail

# ── Full deploy: BigQuery → Ingestion → API → Frontend ───────────────────────
# Usage:
#   export PROJECT_ID=your-project-id
#   export REGION=us-central1   # optional, defaults to us-central1
#   bash scripts/deploy_all.sh

# shellcheck source=_load_env.sh
source "$(dirname "$0")/_load_env.sh"
export PROJECT_ID REGION
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

echo "============================================================"
echo "  Full deploy — project: $PROJECT_ID  region: $REGION"
echo "============================================================"

echo
echo "[ 1/4 ] BigQuery setup"
bash "$SCRIPTS/setup_bigquery.sh"

echo
echo "[ 2/4 ] Ingestion job + scheduler"
bash "$SCRIPTS/deploy_ingestion.sh"

echo
echo "[ 3/4 ] API"
# Source so API_URL is exported into this shell for the frontend step
source "$SCRIPTS/deploy_api.sh"

echo
echo "[ 4/4 ] Frontend"
bash "$SCRIPTS/deploy_frontend.sh"

echo
echo "============================================================"
echo "  All done."
echo "============================================================"

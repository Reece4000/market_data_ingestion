#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
# shellcheck source=_load_env.sh
source "$(dirname "$0")/_load_env.sh"
SA="market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Deploying API for project: $PROJECT_ID"

# ── Build + push image ────────────────────────────────────────────────────────
echo "--> Building and pushing API image..."
gcloud builds submit "$ROOT/api" \
  --tag "gcr.io/$PROJECT_ID/market-api" \
  --project="$PROJECT_ID"

# ── Deploy to Cloud Run ───────────────────────────────────────────────────────
echo "--> Deploying to Cloud Run..."
gcloud run services deploy market-api \
  --image "gcr.io/$PROJECT_ID/market-api" \
  --region "$REGION" \
  --allow-unauthenticated \
  --service-account "$SA" \
  --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,BQ_DATASET=market_data" \
  --project="$PROJECT_ID"

# ── Print the deployed URL ────────────────────────────────────────────────────
API_URL=$(gcloud run services describe market-api \
  --region "$REGION" \
  --format='value(status.url)' \
  --project="$PROJECT_ID")

echo "==> API deployed at: $API_URL"
echo "    Health check: $API_URL/health"
echo "    Docs:         $API_URL/docs"

# Export so deploy_all.sh can read it
export API_URL

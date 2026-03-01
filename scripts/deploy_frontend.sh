#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
# shellcheck source=_load_env.sh
source "$(dirname "$0")/_load_env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# VITE_API_URL can be passed in or auto-detected from the deployed API service
if [ -z "${API_URL:-}" ]; then
  echo "--> API_URL not set, fetching from deployed market-api service..."
  API_URL=$(gcloud run services describe market-api \
    --region "$REGION" \
    --format='value(status.url)' \
    --project="$PROJECT_ID")
fi

echo "==> Deploying frontend for project: $PROJECT_ID"
echo "    API URL: $API_URL"

# ── Build image locally (gcloud builds submit doesn't support --build-arg) ────
echo "--> Building frontend image with VITE_API_URL baked in..."
docker build \
  --build-arg "VITE_API_URL=$API_URL" \
  -t "gcr.io/$PROJECT_ID/market-frontend" \
  "$ROOT/frontend"

# ── Push to Container Registry ────────────────────────────────────────────────
echo "--> Pushing image..."
docker push "gcr.io/$PROJECT_ID/market-frontend"

# ── Deploy to Cloud Run ───────────────────────────────────────────────────────
echo "--> Deploying to Cloud Run..."
gcloud run services deploy market-frontend \
  --image "gcr.io/$PROJECT_ID/market-frontend" \
  --region "$REGION" \
  --allow-unauthenticated \
  --project="$PROJECT_ID"

# ── Print the deployed URL ────────────────────────────────────────────────────
FRONTEND_URL=$(gcloud run services describe market-frontend \
  --region "$REGION" \
  --format='value(status.url)' \
  --project="$PROJECT_ID")

echo "==> Frontend deployed at: $FRONTEND_URL"

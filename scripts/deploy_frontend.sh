#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
# shellcheck source=_load_env.sh
source "$(dirname "$0")/_load_env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIREBASE_API_KEY="${FIREBASE_API_KEY:-}"
FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN:-}"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-$PROJECT_ID}"
FIREBASE_APP_ID="${FIREBASE_APP_ID:-}"

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

if [ -z "$FIREBASE_API_KEY" ] || [ -z "$FIREBASE_AUTH_DOMAIN" ] || [ -z "$FIREBASE_APP_ID" ]; then
  echo "ERROR: FIREBASE_API_KEY, FIREBASE_AUTH_DOMAIN, and FIREBASE_APP_ID are required in .env." >&2
  exit 1
fi

# ── Build + push image with Cloud Build (linux/amd64 compatible for Cloud Run) ──
echo "--> Building frontend image with Cloud Build..."
gcloud builds submit "$ROOT/frontend" \
  --config="$ROOT/frontend/cloudbuild.yaml" \
  --substitutions="_VITE_API_URL=$API_URL,_VITE_FIREBASE_API_KEY=$FIREBASE_API_KEY,_VITE_FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN,_VITE_FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID,_VITE_FIREBASE_APP_ID=$FIREBASE_APP_ID" \
  --project="$PROJECT_ID"

# ── Deploy to Cloud Run ───────────────────────────────────────────────────────
echo "--> Deploying to Cloud Run..."
gcloud run deploy market-frontend \
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

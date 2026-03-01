#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
# shellcheck source=_load_env.sh
source "$(dirname "$0")/_load_env.sh"
SA="market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Deploying ingestion job for project: $PROJECT_ID"

# ── Build + push image ────────────────────────────────────────────────────────
echo "--> Building and pushing ingestion image..."
gcloud builds submit "$ROOT/ingestion" \
  --tag "gcr.io/$PROJECT_ID/market-ingestion" \
  --project="$PROJECT_ID"

# ── Create or update Cloud Run Job ───────────────────────────────────────────
echo "--> Deploying Cloud Run Job..."
if gcloud run jobs describe market-ingestion --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
  gcloud run jobs update market-ingestion \
    --image "gcr.io/$PROJECT_ID/market-ingestion" \
    --region "$REGION" \
    --service-account "$SA" \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,BQ_DATASET=market_data" \
    --project="$PROJECT_ID"
else
  gcloud run jobs create market-ingestion \
    --image "gcr.io/$PROJECT_ID/market-ingestion" \
    --region "$REGION" \
    --service-account "$SA" \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,BQ_DATASET=market_data" \
    --project="$PROJECT_ID"
fi

# ── Run once to seed data ─────────────────────────────────────────────────────
echo "--> Running ingestion job once to seed raw_prices (this may take a minute)..."
gcloud run jobs execute market-ingestion \
  --region "$REGION" \
  --project="$PROJECT_ID" \
  --wait

# ── Run stored procedures to populate technical_indicators ────────────────────
echo "--> Running sp_run_all to populate technical_indicators..."
bq query --use_legacy_sql=false --project_id="$PROJECT_ID" \
  "CALL \`$PROJECT_ID.market_data.sp_run_all\`()"

# ── Grant SA permission to invoke Cloud Run Jobs ──────────────────────────────
echo "--> Granting run.invoker role to service account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/run.invoker"

# ── Create or update Cloud Scheduler job ─────────────────────────────────────
echo "--> Scheduling daily ingestion at 6pm weekdays..."
SCHEDULER_URI="https://$REGION-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/$PROJECT_ID/jobs/market-ingestion:run"

if gcloud scheduler jobs describe market-ingestion-schedule --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
  gcloud scheduler jobs update http market-ingestion-schedule \
    --schedule="0 18 * * 1-5" \
    --uri="$SCHEDULER_URI" \
    --message-body='{}' \
    --oauth-service-account-email="$SA" \
    --location="$REGION" \
    --project="$PROJECT_ID"
else
  gcloud scheduler jobs create http market-ingestion-schedule \
    --schedule="0 18 * * 1-5" \
    --uri="$SCHEDULER_URI" \
    --message-body='{}' \
    --oauth-service-account-email="$SA" \
    --location="$REGION" \
    --project="$PROJECT_ID"
fi

echo "==> Ingestion job deployed and scheduled."

#!/usr/bin/env bash
set -euo pipefail

# Loads .env, exports Terraform variables, then runs terraform init + apply.
# Pass any extra terraform flags as arguments, e.g.:
#   bash scripts/tf_apply.sh -auto-approve
#   bash scripts/tf_apply.sh -target=google_bigquery_dataset.market_data

# shellcheck source=_load_env.sh
source "$(dirname "$0")/_load_env.sh"

# GOOGLE_APPLICATION_CREDENTIALS in .env points to sa-key.json for application
# code running in Docker. Unset it here so it doesn't interfere with gcloud CLI
# commands in this script (Terraform auth is handled via sa-key.json in main.tf).
unset GOOGLE_APPLICATION_CREDENTIALS

# Map .env vars → Terraform input variables
export TF_VAR_project_id="$GCP_PROJECT_ID"
export TF_VAR_region="${REGION:-us-central1}"
export TF_VAR_bq_dataset="${BQ_DATASET:-market_data}"
export TF_VAR_symbols_stock="${SYMBOLS_STOCK:-AAPL,MSFT,NVDA,SPY}"
export TF_VAR_symbols_crypto="${SYMBOLS_CRYPTO:-bitcoin,ethereum}"
export TF_VAR_firebase_project_id="${FIREBASE_PROJECT_ID:-$GCP_PROJECT_ID}"
export TF_VAR_firebase_api_key="${FIREBASE_API_KEY:-}"
export TF_VAR_firebase_auth_domain="${FIREBASE_AUTH_DOMAIN:-}"
export TF_VAR_firebase_app_id="${FIREBASE_APP_ID:-}"
export TF_VAR_api_rate_limit_per_min="${API_RATE_LIMIT_PER_MIN:-240}"
export TF_VAR_watchlist_write_rate_limit_per_min="${WATCHLIST_WRITE_RATE_LIMIT_PER_MIN:-20}"
export TF_VAR_symbols_cache_ttl_seconds="${SYMBOLS_CACHE_TTL_SECONDS:-300}"
export TF_VAR_watchlist_cache_ttl_seconds="${WATCHLIST_CACHE_TTL_SECONDS:-30}"

if [ -z "$TF_VAR_firebase_api_key" ] || [ -z "$TF_VAR_firebase_auth_domain" ] || [ -z "$TF_VAR_firebase_app_id" ]; then
  echo "ERROR: FIREBASE_API_KEY, FIREBASE_AUTH_DOMAIN, and FIREBASE_APP_ID must be set in .env before Terraform deploy." >&2
  exit 1
fi

TERRAFORM_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"

# Bootstrap: Cloud Resource Manager API must exist before Terraform can call any
# GCP API, including the one that enables other APIs. There is no way for
# Terraform to enable it itself — this is the irreducible one-time bootstrap step.
echo "--> Ensuring Cloud Resource Manager API is enabled..."
gcloud services enable cloudresourcemanager.googleapis.com \
  --project="$GCP_PROJECT_ID" --quiet

echo "--> Configuring Docker to authenticate with GCR..."
gcloud auth configure-docker --quiet

echo "==> Terraform apply — project: $TF_VAR_project_id  region: $TF_VAR_region"
echo "    Working dir: $TERRAFORM_DIR"

cd "$TERRAFORM_DIR"

# Init (safe to re-run — skips if already initialised)
terraform init -upgrade

terraform apply "$@"

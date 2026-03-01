#!/usr/bin/env bash
# Sourced by other scripts — not run directly.
# Loads .env from the project root and maps GCP_PROJECT_ID → PROJECT_ID.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  # Export each non-comment, non-blank line
  set -o allexport
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +o allexport
else
  echo "ERROR: .env not found at $ENV_FILE" >&2
  exit 1
fi

# Map GCP_PROJECT_ID → PROJECT_ID (scripts use PROJECT_ID; .env uses GCP_PROJECT_ID)
PROJECT_ID="${PROJECT_ID:-$GCP_PROJECT_ID}"
REGION="${REGION:-us-central1}"

if [ -z "$PROJECT_ID" ]; then
  echo "ERROR: GCP_PROJECT_ID is not set in .env" >&2
  exit 1
fi

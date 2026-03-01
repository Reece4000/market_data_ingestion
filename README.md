# Market Prep — Data Engineering Learning Project

Stack: Cloud Run · BigQuery · Stored Procedures · FastAPI · React · Firestore · Docker

## Architecture

```
yfinance + CoinGecko
        ↓
Cloud Run Job (ingestion/main.py)     ← Cloud Scheduler daily
        ↓
BigQuery: raw_prices
        ↓
Stored Procedures → technical_indicators
        ↓
FastAPI ←→ Firestore (watchlists)
        ↓
React frontend (Recharts)
```

---

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated: `gcloud auth application-default login`
- Docker Desktop
- Node 18+, Python 3.11+

---

## 1. One-time GCP Setup

```bash
export PROJECT_ID=your-project-id

# Enable required APIs
gcloud services enable bigquery.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  firestore.googleapis.com \
  --project=$PROJECT_ID

# Create Firestore database (Native mode, us-central1)
gcloud firestore databases create --location=nam5 --project=$PROJECT_ID

# Create a service account for local use
gcloud iam service-accounts create market-prep-sa \
  --display-name="Market Prep SA" --project=$PROJECT_ID

# Grant roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

# Download key for local use
gcloud iam service-accounts keys create ./sa-key.json \
  --iam-account=market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com
```

---

## 2. BigQuery Setup

```bash
# Replace YOUR_PROJECT_ID in all SQL files, then run setup
export PROJECT_ID=your-project-id

sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" bigquery/setup.sql \
  | bq query --use_legacy_sql=false --project_id=$PROJECT_ID

# Create stored procedures (run each one)
for f in bigquery/procedures/*.sql; do
  echo "Running $f..."
  sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$f" \
    | bq query --use_legacy_sql=false --project_id=$PROJECT_ID
done

# Create view
sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" bigquery/views/vw_latest_indicators.sql \
  | bq query --use_legacy_sql=false --project_id=$PROJECT_ID
```

---

## 3. Run Ingestion Locally

```bash
cp .env.example .env
# Edit .env with your project ID

cd ingestion
pip install -r requirements.txt
python main.py

# Or with Docker:
docker build -t market-ingestion ./ingestion
docker run --env-file .env -v $(pwd)/sa-key.json:/app/sa-key.json market-ingestion
```

## 4. Run Stored Procedures

```bash
bq query --use_legacy_sql=false \
  "CALL \`$PROJECT_ID.market_data.sp_run_all\`()"
```

---

## 5. Local Development (native — fastest iteration)

```bash
# API
cd api && pip install -r requirements.txt
uvicorn main:app --reload --port 8000

# Frontend (separate terminal)
cd frontend && npm install && npm run dev
# → http://localhost:5173
```

---

## 6. Local Development with Docker

```bash
cp .env.example .env  # fill in project ID
docker-compose up --build
# API  → http://localhost:8000/docs
# App  → http://localhost:3000
```

---

## 7. Deploy to Cloud Run

**Use Terraform — it handles everything:**

```bash
cp .env.example .env   # fill in GCP_PROJECT_ID
bash scripts/tf_apply.sh
```

This provisions all GCP resources, builds and pushes images via Cloud Build, and deploys all services in the correct order. Outputs the frontend and API URLs when complete.

<details>
<summary>Manual gcloud equivalent (for reference only)</summary>

```bash
export PROJECT_ID=your-project-id
export REGION=us-central1

# Ingestion
gcloud builds submit ./ingestion --tag gcr.io/$PROJECT_ID/market-ingestion --project=$PROJECT_ID
gcloud run jobs create market-ingestion \
  --image gcr.io/$PROJECT_ID/market-ingestion --region $REGION \
  --service-account market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars GCP_PROJECT_ID=$PROJECT_ID,BQ_DATASET=market_data \
  --project=$PROJECT_ID

# API
gcloud builds submit ./api --tag gcr.io/$PROJECT_ID/market-api --project=$PROJECT_ID
gcloud run services deploy market-api \
  --image gcr.io/$PROJECT_ID/market-api --region $REGION \
  --allow-unauthenticated \
  --service-account market-prep-sa@$PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars GCP_PROJECT_ID=$PROJECT_ID,BQ_DATASET=market_data \
  --project=$PROJECT_ID

# Frontend — must use cloudbuild.yaml to pass build args
API_URL=$(gcloud run services describe market-api --region $REGION --format='value(status.url)' --project=$PROJECT_ID)
gcloud builds submit ./frontend \
  --config=frontend/cloudbuild.yaml \
  --substitutions=_VITE_API_URL=$API_URL \
  --project=$PROJECT_ID
gcloud run services deploy market-frontend \
  --image gcr.io/$PROJECT_ID/market-frontend --region $REGION \
  --allow-unauthenticated --project=$PROJECT_ID
```
</details>

---

## Key Learning Points

| Concept | Where to look |
|---------|--------------|
| BQ windowed aggregations (SMA, BB) | `bigquery/procedures/sp_moving_averages.sql`, `sp_bollinger_bands.sql` |
| BQ recursive CTEs (EMA) | `bigquery/procedures/sp_moving_averages.sql` |
| `CREATE OR REPLACE PROCEDURE` + `BEGIN/END` | All `sp_*.sql` files |
| `CALL` to orchestrate procedures | `bigquery/procedures/sp_run_all.sql` |
| `MERGE` for upsert | All stored procedures |
| Firestore read/write (NoSQL) | `api/routers/watchlist.py` |
| Cloud Run Jobs vs Services | Ingestion = Job, API = Service |
| Multi-stage Docker builds | `frontend/Dockerfile` |
| FastAPI routing + CORS | `api/main.py` |
| Recharts with real data | `frontend/src/components/PriceChart.jsx` |

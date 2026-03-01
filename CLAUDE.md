# Market Prep — Project Context for Claude

## What this project is

A learning project to prepare for a data engineering role. The company uses:
BigQuery (heavy stored procedures), FastAPI + React + Firestore for internal tools, Docker for everything, GCP for deployment.

Goal: get hands-on with all of it before day one. Learning is the primary aim — not production polish.

## Stack

| Layer | Tech | Why |
|-------|------|-----|
| Data sources | yfinance (stocks), CoinGecko API (crypto) | Free, no API key |
| Ingestion | Python Cloud Run Job | Scheduled daily, runs to completion |
| Data warehouse | BigQuery — `market_data` dataset | Core skill to develop |
| Orchestration | BigQuery Stored Procedures | Core skill to develop |
| Backend | FastAPI (Python) | Mirrors company stack |
| NoSQL | Firestore | Mirrors company stack (watchlists) |
| Frontend | React + Recharts + Vite | Company uses React; learning from scratch |
| Containers | Docker + docker-compose | Mirrors company stack |
| Deploy | Cloud Run (Jobs + Services) | GCP already set up |

## Architecture

```
yfinance + CoinGecko
        ↓
Cloud Run Job (ingestion/main.py)     ← Cloud Scheduler 6pm weekdays
        ↓
BigQuery: market_data.raw_prices
        ↓
sp_run_all() → sp_moving_averages, sp_rsi, sp_macd, sp_bollinger_bands
        ↓
BigQuery: market_data.technical_indicators
        ↓
FastAPI (/api/prices, /api/indicators, /api/watchlist)
        ↓ ↕ Firestore (watchlists/default)
React frontend (Recharts charts + watchlist sidebar)
```

## Project structure

```
prep_project/
├── CLAUDE.md                    ← you are here
├── README.md                    ← full setup + deploy commands
├── .env.example                 ← copy to .env, fill in project ID
├── docker-compose.yml           ← local: api:8000 + frontend:3000
├── sa-key.json                  ← NOT committed — local service account key
│
├── ingestion/
│   ├── main.py                  ← fetches stock/crypto, writes to BQ raw_prices
│   ├── requirements.txt
│   └── Dockerfile               ← python:3.11-slim, CMD python main.py
│
├── bigquery/
│   ├── setup.sql                ← CREATE dataset + raw_prices + technical_indicators tables
│   ├── procedures/
│   │   ├── sp_moving_averages.sql   ← SMA (window func) + EMA (recursive CTE) → MERGE
│   │   ├── sp_rsi.sql               ← LAG + sliding AVG window → MERGE
│   │   ├── sp_macd.sql              ← reads ema_12/ema_26, computes signal via recursive CTE
│   │   ├── sp_bollinger_bands.sql   ← STDDEV_POP window func → MERGE
│   │   └── sp_run_all.sql           ← orchestrator: CALL each proc in order
│   └── views/
│       └── vw_latest_indicators.sql ← latest row per symbol + close price join
│
├── api/
│   ├── main.py                  ← FastAPI app, CORS, mounts routers
│   ├── requirements.txt
│   ├── Dockerfile               ← python:3.11-slim, uvicorn
│   └── routers/
│       ├── prices.py            ← GET /api/symbols, GET /api/prices/{symbol}
│       ├── indicators.py        ← GET /api/indicators/{symbol}[/latest]
│       └── watchlist.py         ← GET/POST/DELETE /api/watchlist — Firestore
│
└── frontend/
    ├── package.json             ← react, recharts, axios, vite
    ├── vite.config.js           ← proxy /api → localhost:8000 in dev
    ├── index.html
    ├── Dockerfile               ← multi-stage: node build → nginx:alpine serve
    ├── nginx.conf
    └── src/
        ├── main.jsx
        ├── App.jsx              ← layout: header + chart area + watchlist sidebar
        ├── api.js               ← all axios calls in one place
        ├── App.css / index.css  ← dark theme
        └── components/
            ├── PriceChart.jsx   ← Recharts LineChart, RSI sub-chart, overlay toggles
            ├── SymbolSelector.jsx ← <select> populated from /api/symbols
            └── Watchlist.jsx    ← Firestore-backed watchlist with add/remove

```

## Current status

Scaffolded — nothing deployed or run yet. All files written, nothing tested.

## Next steps (pick up here)

1. **GCP setup** (one-time)
   - Enable APIs, create service account, download `sa-key.json`
   - See README section 1 for exact commands

2. **BigQuery setup**
   ```bash
   export PROJECT_ID=your-project-id
   sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" bigquery/setup.sql | bq query --use_legacy_sql=false
   for f in bigquery/procedures/*.sql bigquery/views/*.sql; do
     sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" "$f" | bq query --use_legacy_sql=false
   done
   ```

3. **Run ingestion locally**
   ```bash
   cp .env.example .env  # set GCP_PROJECT_ID
   cd ingestion && pip install -r requirements.txt && python main.py
   ```

4. **Run stored procedures**
   ```bash
   bq query --use_legacy_sql=false "CALL \`$PROJECT_ID.market_data.sp_run_all\`()"
   ```

5. **Start API + frontend for local dev**
   ```bash
   cd api && pip install -r requirements.txt && uvicorn main:app --reload --port 8000
   cd frontend && npm install && npm run dev   # → http://localhost:5173
   ```

6. **Deploy to Cloud Run** (see README section 7)

## Key things to know

- `YOUR_PROJECT_ID` is a placeholder in all SQL files — replace before running (use sed, see README)
- `sa-key.json` goes in the project root for local auth — add to `.gitignore`
- In Cloud Run, auth uses the attached service account — no key file needed
- The Vite dev server proxies `/api` to `localhost:8000` — no CORS issues locally
- `sp_macd` must run AFTER `sp_moving_averages` (reads ema_12/ema_26 from the table)
- Firestore must be initialised in Native mode before the API will work (see README step 1)
- CoinGecko free tier doesn't give OHLCV — crypto rows have open=high=low=close (just price)

## Learning pointers

- **Recursive CTE (EMA)**: `bigquery/procedures/sp_moving_averages.sql` lines with `WITH RECURSIVE`
- **MERGE (upsert)**: every stored procedure uses it — understand WHEN MATCHED vs NOT MATCHED
- **Firestore patterns**: `api/routers/watchlist.py` — ArrayUnion/ArrayRemove are key
- **Multi-stage Docker**: `frontend/Dockerfile` — build stage vs serve stage
- **Cloud Run Job vs Service**: ingestion = Job (runs to completion), API = Service (stays up)

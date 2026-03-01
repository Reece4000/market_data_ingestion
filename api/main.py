from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import indicators, prices, watchlist

app = FastAPI(
    title="Market Prep API",
    description="Serves price + indicator data from BigQuery and watchlists from Firestore",
    version="0.1.0",
)

# Allow requests from local dev and Cloud Run frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(prices.router, prefix="/api", tags=["prices"])
app.include_router(indicators.router, prefix="/api", tags=["indicators"])
app.include_router(watchlist.router, prefix="/api", tags=["watchlist"])


@app.get("/health")
def health_check():
    return {"status": "ok"}

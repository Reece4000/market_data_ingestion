import os
import threading
import time
from collections import deque

from fastapi import FastAPI
from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from routers import indicators, prices, watchlist

app = FastAPI(
    title="Market Prep API",
    description="Serves price + indicator data from BigQuery and watchlists from Firestore",
    version="0.1.0",
)

API_RATE_LIMIT_PER_MIN = int(os.environ.get("API_RATE_LIMIT_PER_MIN", "240"))
_rate_hits_by_ip: dict[str, deque[float]] = {}
_rate_hits_lock = threading.Lock()

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


@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    if request.url.path == "/health":
        return await call_next(request)

    now = time.time()
    cutoff = now - 60
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        client_ip = forwarded_for.split(",")[0].strip()
    elif request.client and request.client.host:
        client_ip = request.client.host
    else:
        client_ip = "unknown"

    with _rate_hits_lock:
        hits = _rate_hits_by_ip.setdefault(client_ip, deque())
        while hits and hits[0] < cutoff:
            hits.popleft()
        if len(hits) >= API_RATE_LIMIT_PER_MIN:
            return JSONResponse(status_code=429, content={"detail": "Too many requests"})
        hits.append(now)

    return await call_next(request)


@app.get("/health")
def health_check():
    return {"status": "ok"}

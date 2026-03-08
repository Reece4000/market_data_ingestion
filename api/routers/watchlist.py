"""
Watchlist router — reads and writes per-user watchlists in Firestore.

Auth:
  - Expects Firebase ID token in Authorization header (Bearer <token>)
  - Verifies token server-side with firebase-admin
"""

import os
import threading
import time
from collections import deque

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials, get_app, initialize_app
from google.cloud import firestore
from pydantic import BaseModel

router = APIRouter()

# Firestore client uses ADC (Application Default Credentials) automatically.
db = firestore.Client()

FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", os.environ.get("GCP_PROJECT_ID", ""))
WATCHLIST_CACHE_TTL_SECONDS = int(os.environ.get("WATCHLIST_CACHE_TTL_SECONDS", "30"))
WATCHLIST_WRITE_RATE_LIMIT_PER_MIN = int(os.environ.get("WATCHLIST_WRITE_RATE_LIMIT_PER_MIN", "20"))

# Initialize Firebase Admin once (ADC on Cloud Run service account).
try:
    get_app()
except ValueError:
    if FIREBASE_PROJECT_ID:
        initialize_app(credentials.ApplicationDefault(), {"projectId": FIREBASE_PROJECT_ID})
    else:
        initialize_app(credentials.ApplicationDefault())

_watchlist_cache_by_uid: dict[str, tuple[list[str], float]] = {}
_watchlist_cache_lock = threading.Lock()

_write_hits_by_ip: dict[str, deque[float]] = {}
_write_hits_lock = threading.Lock()


def _extract_client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def _require_authenticated_uid(
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")

    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")

    try:
        decoded = firebase_auth.verify_id_token(token, check_revoked=False)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid authentication token") from exc

    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Authentication token missing uid")
    return uid


def _enforce_watchlist_write_limit(request: Request) -> None:
    now = time.time()
    cutoff = now - 60
    client_ip = _extract_client_ip(request)

    with _write_hits_lock:
        hits = _write_hits_by_ip.setdefault(client_ip, deque())
        while hits and hits[0] < cutoff:
            hits.popleft()
        if len(hits) >= WATCHLIST_WRITE_RATE_LIMIT_PER_MIN:
            raise HTTPException(status_code=429, detail="Too many watchlist write requests")
        hits.append(now)


def _watchlist_doc(uid: str):
    return db.collection("watchlists").document(uid)


class SymbolRequest(BaseModel):
    symbol: str


@router.get("/watchlist")
def get_watchlist(uid: str = Depends(_require_authenticated_uid)):
    """Fetch the authenticated user's watchlist from Firestore."""
    now = time.time()
    with _watchlist_cache_lock:
        cached = _watchlist_cache_by_uid.get(uid)
        if cached and now < cached[1]:
            return {"symbols": cached[0]}

    doc = _watchlist_doc(uid).get()
    if not doc.exists:
        symbols: list[str] = []
    else:
        symbols = doc.to_dict().get("symbols", [])

    with _watchlist_cache_lock:
        _watchlist_cache_by_uid[uid] = (symbols, time.time() + WATCHLIST_CACHE_TTL_SECONDS)
    return {"symbols": symbols}


@router.post("/watchlist")
def add_to_watchlist(
    req: SymbolRequest,
    uid: str = Depends(_require_authenticated_uid),
    _: None = Depends(_enforce_watchlist_write_limit),
):
    """Add a symbol to the authenticated user's watchlist."""
    _watchlist_doc(uid).set(
        {"symbols": firestore.ArrayUnion([req.symbol.upper()])},
        merge=True,
    )
    with _watchlist_cache_lock:
        _watchlist_cache_by_uid.pop(uid, None)
    return {"message": f"Added {req.symbol.upper()} to watchlist"}


@router.delete("/watchlist/{symbol}")
def remove_from_watchlist(
    symbol: str,
    uid: str = Depends(_require_authenticated_uid),
    _: None = Depends(_enforce_watchlist_write_limit),
):
    """Remove a symbol from the authenticated user's watchlist."""
    _watchlist_doc(uid).set(
        {"symbols": firestore.ArrayRemove([symbol.upper()])},
        merge=True,
    )
    with _watchlist_cache_lock:
        _watchlist_cache_by_uid.pop(uid, None)
    return {"message": f"Removed {symbol.upper()} from watchlist"}

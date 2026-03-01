"""
Watchlist router — reads and writes to Firestore.

Firestore is a NoSQL document database. Data lives in:
  Collection: watchlists
  Document:   default
  Fields:     { symbols: ["AAPL", "MSFT", ...] }

Key Firestore patterns:
  - db.collection("watchlists").document("default")  → document reference
  - doc_ref.get()                                     → read document snapshot
  - doc_ref.set(..., merge=True)                      → partial update (merge)
  - firestore.ArrayUnion([...])                       → atomically append to array
  - firestore.ArrayRemove([...])                      → atomically remove from array
"""

from fastapi import APIRouter
from google.cloud import firestore
from pydantic import BaseModel

router = APIRouter()

# Firestore client uses ADC (Application Default Credentials) automatically
db = firestore.Client()

WATCHLIST_DOC = db.collection("watchlists").document("default")


class SymbolRequest(BaseModel):
    symbol: str


@router.get("/watchlist")
def get_watchlist():
    """Fetch the saved watchlist from Firestore."""
    doc = WATCHLIST_DOC.get()
    if not doc.exists:
        return {"symbols": []}
    return {"symbols": doc.to_dict().get("symbols", [])}


@router.post("/watchlist")
def add_to_watchlist(req: SymbolRequest):
    """
    Add a symbol to the watchlist.
    ArrayUnion ensures no duplicates and is atomic (safe for concurrent writes).
    merge=True means we don't overwrite the whole document.
    """
    WATCHLIST_DOC.set(
        {"symbols": firestore.ArrayUnion([req.symbol.upper()])},
        merge=True,
    )
    return {"message": f"Added {req.symbol.upper()} to watchlist"}


@router.delete("/watchlist/{symbol}")
def remove_from_watchlist(symbol: str):
    """Remove a symbol from the watchlist using atomic ArrayRemove."""
    WATCHLIST_DOC.set(
        {"symbols": firestore.ArrayRemove([symbol.upper()])},
        merge=True,
    )
    return {"message": f"Removed {symbol.upper()} from watchlist"}

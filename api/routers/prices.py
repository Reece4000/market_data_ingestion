"""
Prices router — queries raw_prices from BigQuery.

Key patterns:
  - google.cloud.bigquery.Client for querying BQ
  - Parameterised queries (ScalarQueryParameter) to avoid SQL injection
  - .result() blocks until the query completes, then returns a RowIterator
"""

import os

from fastapi import APIRouter, HTTPException
from google.cloud import bigquery

router = APIRouter()

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
DATASET = os.environ.get("BQ_DATASET", "market_data")

# Client is created once at module load — reused across requests
client = bigquery.Client(project=PROJECT_ID)


@router.get("/symbols")
def get_symbols():
    """Return all distinct symbols + their asset type."""
    query = f"""
        SELECT DISTINCT symbol, asset_type
        FROM `{PROJECT_ID}.{DATASET}.raw_prices`
        ORDER BY asset_type, symbol
    """
    rows = client.query(query).result()
    return [{"symbol": row.symbol, "asset_type": row.asset_type} for row in rows]


@router.get("/prices/{symbol}")
def get_prices(symbol: str, days: int = 90):
    """
    Return daily OHLCV rows for a symbol over the past N days.

    Uses parameterised query — never interpolate user input directly into SQL.
    """
    if days < 1 or days > 1825:
        raise HTTPException(status_code=400, detail="days must be between 1 and 1825")

    query = f"""
        SELECT date, open, high, low, close, volume
        FROM `{PROJECT_ID}.{DATASET}.raw_prices`
        WHERE symbol = @symbol
          AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL @days DAY)
        ORDER BY date ASC
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("symbol", "STRING", symbol.upper()),
            bigquery.ScalarQueryParameter("days", "INT64", days),
        ]
    )
    rows = client.query(query, job_config=job_config).result()
    return [
        {
            "date": str(row.date),
            "open": row.open,
            "high": row.high,
            "low": row.low,
            "close": row.close,
            "volume": row.volume,
        }
        for row in rows
    ]

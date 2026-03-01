"""
Indicators router — queries technical_indicators from BigQuery.
"""

import os

from fastapi import APIRouter, HTTPException
from google.cloud import bigquery

router = APIRouter()

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
DATASET = os.environ.get("BQ_DATASET", "market_data")

client = bigquery.Client(project=PROJECT_ID)


@router.get("/indicators/{symbol}")
def get_indicators(symbol: str, days: int = 90):
    """Return technical indicator rows for a symbol over the past N days."""
    if days < 1 or days > 1825:
        raise HTTPException(status_code=400, detail="days must be between 1 and 1825")

    query = f"""
        SELECT
            date,
            sma_20, sma_50, sma_200,
            ema_12, ema_26,
            rsi_14,
            macd, macd_signal, macd_histogram,
            bb_upper, bb_lower
        FROM `{PROJECT_ID}.{DATASET}.technical_indicators`
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
            "sma_20": row.sma_20,
            "sma_50": row.sma_50,
            "sma_200": row.sma_200,
            "ema_12": row.ema_12,
            "ema_26": row.ema_26,
            "rsi_14": row.rsi_14,
            "macd": row.macd,
            "macd_signal": row.macd_signal,
            "macd_histogram": row.macd_histogram,
            "bb_upper": row.bb_upper,
            "bb_lower": row.bb_lower,
        }
        for row in rows
    ]


@router.get("/indicators/{symbol}/latest")
def get_latest_indicators(symbol: str):
    """Return the single most recent indicator row for a symbol."""
    query = f"""
        SELECT *
        FROM `{PROJECT_ID}.{DATASET}.vw_latest_indicators`
        WHERE symbol = @symbol
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("symbol", "STRING", symbol.upper()),
        ]
    )
    rows = list(client.query(query, job_config=job_config).result())
    if not rows:
        raise HTTPException(status_code=404, detail=f"No data for symbol {symbol}")
    row = rows[0]
    return dict(row.items())

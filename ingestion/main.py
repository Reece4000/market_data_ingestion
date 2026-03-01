"""
Cloud Run Job — Market Data Ingestion

Fetches OHLCV data from:
  - Yahoo Finance (yfinance) for stocks — no API key needed
  - CoinGecko v3 public API for crypto — no API key needed

Writes rows to BigQuery: market_data.raw_prices
"""

import logging
import os
from datetime import datetime, timezone

import requests
import yfinance as yf
from google.cloud import bigquery

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
DATASET = os.environ.get("BQ_DATASET", "market_data")
TABLE_ID = f"{PROJECT_ID}.{DATASET}.raw_prices"

STOCK_SYMBOLS = [s.strip() for s in os.environ.get("SYMBOLS_STOCK", "AAPL,MSFT,NVDA,SPY").split(",")]
CRYPTO_IDS = [s.strip() for s in os.environ.get("SYMBOLS_CRYPTO", "bitcoin,ethereum").split(",")]

COINGECKO_BASE = "https://api.coingecko.com/api/v3"


def fetch_stock_data(symbol: str) -> list[dict]:
    logger.info(f"Fetching stock data: {symbol}")
    ticker = yf.Ticker(symbol)
    hist = ticker.history(period="1y", interval="1d")

    if hist.empty:
        logger.warning(f"No data returned for {symbol}")
        return []

    rows = []
    for date_idx, row in hist.iterrows():
        rows.append({
            "symbol": symbol,
            "asset_type": "stock",
            "date": date_idx.date().isoformat(),
            "open": round(float(row["Open"]), 6),
            "high": round(float(row["High"]), 6),
            "low": round(float(row["Low"]), 6),
            "close": round(float(row["Close"]), 6),
            "volume": float(row["Volume"]),
            "ingested_at": datetime.now(timezone.utc).isoformat(),
        })
    logger.info(f"Fetched {len(rows)} rows for {symbol}")
    return rows


def fetch_crypto_data(coin_id: str) -> list[dict]:
    """
    CoinGecko /market_chart returns arrays of [timestamp_ms, value].
    Free tier only provides daily closing price (not full OHLCV),
    so we store close == open == high == low for crypto.
    """
    logger.info(f"Fetching crypto data: {coin_id}")
    url = f"{COINGECKO_BASE}/coins/{coin_id}/market_chart"
    params = {"vs_currency": "usd", "days": "365", "interval": "daily"}

    resp = requests.get(url, params=params, timeout=30)
    resp.raise_for_status()
    data = resp.json()

    prices = data.get("prices", [])
    volumes_map = {ts: v for ts, v in data.get("total_volumes", [])}

    rows = []
    for ts_ms, price in prices:
        date = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).date()
        close_price = round(float(price), 6)
        rows.append({
            "symbol": coin_id.upper(),
            "asset_type": "crypto",
            "date": date.isoformat(),
            "open": close_price,
            "high": close_price,
            "low": close_price,
            "close": close_price,
            "volume": round(float(volumes_map.get(ts_ms, 0)), 2),
            "ingested_at": datetime.now(timezone.utc).isoformat(),
        })
    logger.info(f"Fetched {len(rows)} rows for {coin_id}")
    return rows


def write_to_bigquery(client: bigquery.Client, rows: list[dict]) -> None:
    if not rows:
        return

    # Deduplicate: keep last occurrence per (symbol, date) before loading.
    # CoinGecko can return the current day twice (partial + final price).
    deduped = {}
    for row in rows:
        deduped[(row["symbol"], row["date"])] = row
    rows = list(deduped.values())

    # WRITE_TRUNCATE replaces raw_prices entirely each run.
    # Since we always fetch a full year per symbol this is safe —
    # no data is lost and streaming-buffer conflicts are avoided.
    load_job = client.load_table_from_json(
        rows,
        TABLE_ID,
        job_config=bigquery.LoadJobConfig(
            write_disposition="WRITE_TRUNCATE",
            autodetect=True,
        ),
    )
    load_job.result()
    logger.info(f"Wrote {len(rows)} rows to {TABLE_ID}")


def main() -> None:
    client = bigquery.Client(project=PROJECT_ID)
    all_rows: list[dict] = []

    for symbol in STOCK_SYMBOLS:
        try:
            all_rows.extend(fetch_stock_data(symbol))
        except Exception as exc:
            logger.error(f"Stock fetch failed for {symbol}: {exc}")

    for coin_id in CRYPTO_IDS:
        try:
            all_rows.extend(fetch_crypto_data(coin_id))
        except Exception as exc:
            logger.error(f"Crypto fetch failed for {coin_id}: {exc}")

    logger.info(f"Total rows to insert: {len(all_rows)}")
    write_to_bigquery(client, all_rows)

    logger.info("Running sp_run_all to refresh technical indicators...")
    client.query(f"CALL `{PROJECT_ID}.{DATASET}.sp_run_all`()").result()
    logger.info("Ingestion complete.")


if __name__ == "__main__":
    main()

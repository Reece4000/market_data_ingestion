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
import uuid
import yfinance as yf
from google.cloud import bigquery



logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
DATASET = os.environ.get("BQ_DATASET", "market_data")
TABLE_ID = f"{PROJECT_ID}.{DATASET}.raw_prices"

STOCK_SYMBOLS = [s.strip() for s in os.environ.get("SYMBOLS_STOCK", "").split(",")]
CRYPTO_IDS = [s.strip() for s in os.environ.get("SYMBOLS_CRYPTO", "").split(",")]

if not STOCK_SYMBOLS and not CRYPTO_IDS:
    logger.warning("No symbols specified in SYMBOLS_STOCK or SYMBOLS_CRYPTO")


COINGECKO_BASE = "https://api.coingecko.com/api/v3"


def fetch_stock_data(symbol: str, lookback_days: int = 365) -> list[dict]:
    logger.info(f"Fetching stock data: {symbol}")
    ticker = yf.Ticker(symbol)
    hist = ticker.history(period=f"{lookback_days}d", interval="1d")

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


def fetch_crypto_data(coin_id: str, lookback_days: int = 365) -> list[dict]:
    """
    CoinGecko /market_chart returns arrays of [timestamp_ms, value].
    Free tier only provides daily closing price (not full OHLCV),
    so we store close == open == high == low for crypto.
    """
    logger.info(f"Fetching crypto data: {coin_id}")
    url = f"{COINGECKO_BASE}/coins/{coin_id}/market_chart"
    params = {"vs_currency": "usd", "days": lookback_days, "interval": "daily"}

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


def write_to_bigquery_upsert(
    client: bigquery.Client,
    rows: list[dict],
    *,
    key_cols: tuple[str, ...] = ("symbol", "date"),
) -> None:
    if not rows:
        return

    # 1) Deduplicate within-batch (keep last occurrence)
    deduped: dict[tuple, dict] = {}
    for r in rows:
        deduped[tuple(r[k] for k in key_cols)] = r
    rows = list(deduped.values())

    # 2) Create a per-run staging table
    # Use a real staging table so MERGE can read it
    staging_table_id = f"{TABLE_ID}__staging_{uuid.uuid4().hex}"

    # Use the target schema (recommended) rather than autodetect
    target_table = client.get_table(TABLE_ID)

    load_job = client.load_table_from_json(
        rows,
        staging_table_id,
        job_config=bigquery.LoadJobConfig(
            write_disposition="WRITE_TRUNCATE",
            schema=target_table.schema,   # avoid autodetect drift
        ),
    )
    load_job.result()

    # 3) MERGE staging into target
    # - Updates all non-key columns
    # - Inserts new rows
    key_cond = " AND ".join([f"T.{k} = S.{k}" for k in key_cols])

    # Build column lists from target schema
    cols = [f.name for f in target_table.schema]
    non_keys = [c for c in cols if c not in key_cols and c != "ingested_at"]

    update_set = ",\n    ".join([f"{c} = S.{c}" for c in non_keys])
    insert_cols = ", ".join(cols)
    insert_vals = ", ".join([f"S.{c}" for c in cols])

    merge_sql = f"""
    MERGE `{TABLE_ID}` T
    USING `{staging_table_id}` S
    ON {key_cond}
    WHEN MATCHED THEN
      UPDATE SET
        {update_set}
    WHEN NOT MATCHED THEN
      INSERT ({insert_cols}) VALUES ({insert_vals})
    """

    client.query(merge_sql).result()

    # 4) Drop staging table
    client.delete_table(staging_table_id, not_found_ok=True)


def main() -> None:
    client = bigquery.Client(project=PROJECT_ID)
    all_rows: list[dict] = []

    last_ingested_dates_map = {
        row["symbol"]: row["max_date"]
        for row in client.query(f"SELECT symbol, MAX(date) AS max_date FROM `{TABLE_ID}` GROUP BY symbol").result()
    }


    for symbol in STOCK_SYMBOLS:
        try:
            last_ingested_date = last_ingested_dates_map.get(symbol)
            lookback_days = (datetime.now(timezone.utc).date() - last_ingested_date).days if last_ingested_date else 365
            all_rows.extend(fetch_stock_data(symbol, lookback_days))
        except Exception as exc:
            logger.error(f"Stock fetch failed for {symbol}: {exc}")

    for coin_id in CRYPTO_IDS:
        try:
            last_ingested_date = last_ingested_dates_map.get(coin_id.upper())
            lookback_days = (datetime.now(timezone.utc).date() - last_ingested_date).days if last_ingested_date else 365
            all_rows.extend(fetch_crypto_data(coin_id, lookback_days))
        except Exception as exc:
            logger.error(f"Crypto fetch failed for {coin_id}: {exc}")

    logger.info(f"Total rows to insert: {len(all_rows)}")
    write_to_bigquery_upsert(client, all_rows)

    logger.info("Running sp_run_all to refresh technical indicators...")
    client.query(f"CALL `{PROJECT_ID}.{DATASET}.sp_run_all`()").result()
    logger.info("Ingestion complete.")


if __name__ == "__main__":
    main()

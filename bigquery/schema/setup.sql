-- BigQuery Setup Script
-- Replace YOUR_PROJECT_ID before running, or use the sed command from README:
--   sed "s/YOUR_PROJECT_ID/$PROJECT_ID/g" bigquery/setup.sql | bq query --use_legacy_sql=false

-- Create dataset
CREATE SCHEMA IF NOT EXISTS `YOUR_PROJECT_ID.market_data`
OPTIONS (
  location = 'US',
  description = 'Raw price data and derived technical indicators'
);

-- Raw OHLCV prices from ingestion
-- Partitioned by date (reduces scan cost on time-range queries)
-- Clustered by symbol (collocates data for per-symbol queries)
CREATE TABLE IF NOT EXISTS `YOUR_PROJECT_ID.market_data.raw_prices` (
  symbol      STRING    NOT NULL OPTIONS (description = 'Ticker or coin ID'),
  asset_type  STRING    NOT NULL OPTIONS (description = 'stock | crypto'),
  date        DATE      NOT NULL,
  open        FLOAT64,
  high        FLOAT64,
  low         FLOAT64,
  close       FLOAT64,
  volume      FLOAT64,
  ingested_at TIMESTAMP
)
PARTITION BY date
CLUSTER BY symbol
OPTIONS (
  description = 'Daily OHLCV data from Yahoo Finance and CoinGecko'
);

-- Derived technical indicators — populated by stored procedures
CREATE TABLE IF NOT EXISTS `YOUR_PROJECT_ID.market_data.technical_indicators` (
  symbol           STRING    NOT NULL,
  date             DATE      NOT NULL,
  -- Moving averages
  sma_20           FLOAT64,
  sma_50           FLOAT64,
  sma_200          FLOAT64,
  ema_12           FLOAT64,
  ema_26           FLOAT64,
  -- RSI
  rsi_14           FLOAT64,
  -- MACD
  macd             FLOAT64,
  macd_signal      FLOAT64,
  macd_histogram   FLOAT64,
  -- Bollinger Bands
  bb_upper         FLOAT64,
  bb_lower         FLOAT64,
  calculated_at    TIMESTAMP
)
PARTITION BY date
CLUSTER BY symbol
OPTIONS (
  description = 'Technical indicators derived by stored procedures'
);

CREATE TABLE IF NOT EXISTS `YOUR_PROJECT_ID.market_data.procedure_audit_log` (
  run_id STRING,
  procedure_name STRING,
  started_at TIMESTAMP,
  finished_at TIMESTAMP,
  duration_seconds FLOAT64,
  rows_merged INT64,
  status STRING,
  error_message STRING
) PARTITION BY DATE(started_at);

CREATE TABLE IF NOT EXISTS `YOUR_PROJECT_ID.market_data.data_quality_report` (
  run_id STRING,
  checked_at TIMESTAMP,
  symbol STRING,
  check_name STRING,
  severity STRING,
  affected_date DATE,
  detail STRING
)
PARTITION BY DATE(checked_at)
CLUSTER BY check_name, symbol;

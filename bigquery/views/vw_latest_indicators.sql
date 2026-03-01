-- View: vw_latest_indicators
--
-- Convenience view: latest indicator row per symbol, joined with latest close price.
-- Useful for dashboards showing "current state" of each tracked asset.

CREATE OR REPLACE VIEW `YOUR_PROJECT_ID.market_data.vw_latest_indicators` AS

WITH latest_dates AS (
  -- Find the most recent date with indicator data for each symbol
  SELECT symbol, MAX(date) AS latest_date
  FROM `YOUR_PROJECT_ID.market_data.technical_indicators`
  GROUP BY symbol
)

SELECT
  ti.symbol,
  ti.date,
  rp.asset_type,
  rp.close          AS latest_close,
  rp.volume         AS latest_volume,
  ti.sma_20,
  ti.sma_50,
  ti.sma_200,
  ti.ema_12,
  ti.ema_26,
  ti.rsi_14,
  ti.macd,
  ti.macd_signal,
  ti.macd_histogram,
  ti.bb_upper,
  ti.bb_lower,
  -- Derived signals (educational — not financial advice)
  CASE
    WHEN rp.close > ti.sma_20 AND ti.sma_20 > ti.sma_50 THEN 'bullish'
    WHEN rp.close < ti.sma_20 AND ti.sma_20 < ti.sma_50 THEN 'bearish'
    ELSE 'neutral'
  END AS trend_signal,
  ti.calculated_at

FROM `YOUR_PROJECT_ID.market_data.technical_indicators` ti
JOIN latest_dates ld
  ON ti.symbol = ld.symbol
 AND ti.date   = ld.latest_date
JOIN `YOUR_PROJECT_ID.market_data.raw_prices` rp
  ON ti.symbol = rp.symbol
 AND ti.date   = rp.date;

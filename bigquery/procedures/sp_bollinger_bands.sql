-- Stored Procedure: sp_bollinger_bands
--
-- Calculates 20-period Bollinger Bands for all symbols.
--
-- Bollinger Bands formula:
--   Middle band = SMA(20)
--   Upper band  = SMA(20) + 2 × σ    where σ = population std dev over 20 periods
--   Lower band  = SMA(20) − 2 × σ
--
-- Uses WINDOW clause to avoid repeating the window definition.
-- STDDEV_POP = population standard deviation (σ), not sample (σ-1).
-- Bollinger's original specification uses population std dev.

CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_bollinger_bands`()
BEGIN

  MERGE `YOUR_PROJECT_ID.market_data.technical_indicators` AS T
  USING (
    SELECT
      symbol,
      date,
      -- Named WINDOW clause keeps the SQL readable
      ROUND(AVG(close) OVER w + 2 * STDDEV_POP(close) OVER w, 4) AS bb_upper,
      ROUND(AVG(close) OVER w - 2 * STDDEV_POP(close) OVER w, 4) AS bb_lower
    FROM `YOUR_PROJECT_ID.market_data.raw_prices`
    -- WINDOW alias: 20-period sliding window, partitioned per symbol
    WINDOW w AS (
      PARTITION BY symbol
      ORDER BY date
      ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    )
  ) AS S
  ON T.symbol = S.symbol AND T.date = S.date

  WHEN MATCHED THEN
    UPDATE SET
      bb_upper      = S.bb_upper,
      bb_lower      = S.bb_lower,
      calculated_at = CURRENT_TIMESTAMP()

  WHEN NOT MATCHED THEN
    INSERT (symbol, date, bb_upper, bb_lower, calculated_at)
    VALUES (S.symbol, S.date, S.bb_upper, S.bb_lower, CURRENT_TIMESTAMP());

END;

-- Stored Procedure: sp_moving_averages
--
-- Calculates SMA 20/50/200 and EMA 12/26 for all symbols.
-- Merges results into technical_indicators (INSERT or UPDATE).
--
-- Key BQ concepts used:
--   AVG() OVER (... ROWS BETWEEN N PRECEDING AND CURRENT ROW)  → sliding window SMA
--   WITH RECURSIVE + UNION ALL                                  → iterative EMA
--   MERGE ... USING ... ON ... WHEN MATCHED / NOT MATCHED       → upsert

CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_moving_averages`()
BEGIN

  -- ── Step 1: SMA (Simple Moving Average) ──────────────────────────────────
  -- Window functions naturally handle sliding windows.
  -- ROWS BETWEEN 19 PRECEDING AND CURRENT ROW = 20-period window.
  CREATE TEMP TABLE temp_sma AS
  SELECT
    symbol,
    date,
    ROUND(AVG(close) OVER (
      PARTITION BY symbol ORDER BY date
      ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ), 4) AS sma_20,
    ROUND(AVG(close) OVER (
      PARTITION BY symbol ORDER BY date
      ROWS BETWEEN 49 PRECEDING AND CURRENT ROW
    ), 4) AS sma_50,
    ROUND(AVG(close) OVER (
      PARTITION BY symbol ORDER BY date
      ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
    ), 4) AS sma_200
  FROM `YOUR_PROJECT_ID.market_data.raw_prices`;


  -- ── Step 2: EMA (Exponential Moving Average) ──────────────────────────────
  -- EMA formula: EMA[i] = α × price[i] + (1 − α) × EMA[i−1]
  -- where α (smoothing factor) = 2 / (period + 1)
  --   EMA-12: α = 2/13 ≈ 0.1538
  --   EMA-26: α = 2/27 ≈ 0.0741
  --
  -- Requires a recursive CTE because each row depends on the previous row.
  -- numbered: assigns row numbers per symbol (1 = oldest date)
  -- Recursive anchor: seed EMA with the closing price of the first row
  -- Recursive step: apply the EMA formula using the previous row's EMA
  CREATE TEMP TABLE temp_ema AS
  WITH RECURSIVE numbered AS (
    SELECT
      symbol,
      date,
      close,
      ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY date) AS rn
    FROM (
      -- Deduplicate: one row per (symbol, date) before numbering rows for recursion
      SELECT symbol, date, AVG(close) AS close
      FROM `YOUR_PROJECT_ID.market_data.raw_prices`
      GROUP BY symbol, date
    )
  ),
  ema_cte AS (
    -- Anchor: seed each symbol with its first (oldest) price
    SELECT symbol, date, rn,
           close AS ema_12,
           close AS ema_26
    FROM numbered
    WHERE rn = 1

    UNION ALL

    -- Recursive step: EMA = α × today's close + (1 − α) × yesterday's EMA
    SELECT
      n.symbol,
      n.date,
      n.rn,
      ROUND((2.0 / 13) * n.close + (1 - 2.0 / 13) * e.ema_12, 6) AS ema_12,
      ROUND((2.0 / 27) * n.close + (1 - 2.0 / 27) * e.ema_26, 6) AS ema_26
    FROM numbered n
    JOIN ema_cte e
      ON n.symbol = e.symbol
     AND n.rn = e.rn + 1
  )
  SELECT symbol, date, ema_12, ema_26
  FROM ema_cte;


  -- ── Step 3: Merge into technical_indicators ────────────────────────────────
  -- MERGE is BigQuery's upsert:
  --   WHEN MATCHED     → row exists, UPDATE it
  --   WHEN NOT MATCHED → new row, INSERT it
  MERGE `YOUR_PROJECT_ID.market_data.technical_indicators` AS T
  USING (
    SELECT
      s.symbol, s.date,
      s.sma_20, s.sma_50, s.sma_200,
      e.ema_12, e.ema_26
    FROM temp_sma s
    JOIN temp_ema e ON s.symbol = e.symbol AND s.date = e.date
  ) AS S
  ON T.symbol = S.symbol AND T.date = S.date

  WHEN MATCHED THEN
    UPDATE SET
      sma_20        = S.sma_20,
      sma_50        = S.sma_50,
      sma_200       = S.sma_200,
      ema_12        = S.ema_12,
      ema_26        = S.ema_26,
      calculated_at = CURRENT_TIMESTAMP()

  WHEN NOT MATCHED THEN
    INSERT (symbol, date, sma_20, sma_50, sma_200, ema_12, ema_26, calculated_at)
    VALUES (S.symbol, S.date, S.sma_20, S.sma_50, S.sma_200, S.ema_12, S.ema_26, CURRENT_TIMESTAMP());


  DROP TABLE IF EXISTS temp_sma;
  DROP TABLE IF EXISTS temp_ema;

END;

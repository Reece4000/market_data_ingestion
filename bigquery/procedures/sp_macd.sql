-- Stored Procedure: sp_macd
--
-- Calculates MACD (Moving Average Convergence/Divergence) for all symbols.
--
-- MACD formula:
--   MACD line    = EMA(12) − EMA(26)           (reads from technical_indicators)
--   Signal line  = EMA(9) of MACD line          (recursive CTE)
--   Histogram    = MACD line − Signal line
--
-- IMPORTANT: Run sp_moving_averages() BEFORE this procedure,
-- because it reads ema_12 and ema_26 from technical_indicators.
--
-- EMA(9) of MACD uses the same recursive pattern as sp_moving_averages:
--   α = 2/(9+1) = 0.2

CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_macd`(v_run_id STRING)
BEGIN
  DECLARE v_started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_finished_at TIMESTAMP;
  DECLARE v_rows_merged INT64 DEFAULT 0;

  BEGIN
    -- Step 1: compute MACD line from stored EMA values, number rows for recursion
    CREATE TEMP TABLE temp_macd_numbered AS
    SELECT
      symbol,
      date,
      ROUND(ema_12 - ema_26, 6) AS macd_line,
      ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY date) AS rn
    FROM `YOUR_PROJECT_ID.market_data.technical_indicators`
    WHERE ema_12 IS NOT NULL
      AND ema_26 IS NOT NULL;


    -- Step 2: EMA(9) of MACD line = Signal line (recursive CTE, same pattern as EMA)
    CREATE TEMP TABLE temp_signal AS
    WITH RECURSIVE signal_cte AS (
      -- Anchor: seed with first MACD value per symbol
      SELECT symbol, date, rn, macd_line, macd_line AS signal_line
      FROM temp_macd_numbered
      WHERE rn = 1

      UNION ALL

      -- Recursive: apply EMA formula. α = 2/(9+1) = 0.2
      SELECT
        n.symbol,
        n.date,
        n.rn,
        n.macd_line,
        ROUND(0.2 * n.macd_line + 0.8 * s.signal_line, 6) AS signal_line
      FROM temp_macd_numbered n
      JOIN signal_cte s
        ON n.symbol = s.symbol
       AND n.rn = s.rn + 1
    )
    SELECT
      symbol,
      date,
      ROUND(macd_line, 4)                       AS macd,
      ROUND(signal_line, 4)                     AS macd_signal,
      ROUND(macd_line - signal_line, 4)         AS macd_histogram
    FROM signal_cte;


    -- Step 3: Merge into technical_indicators
    MERGE `YOUR_PROJECT_ID.market_data.technical_indicators` AS T
    USING temp_signal AS S
    ON T.symbol = S.symbol AND T.date = S.date
    WHEN MATCHED THEN
      UPDATE SET
        macd           = S.macd,
        macd_signal    = S.macd_signal,
        macd_histogram = S.macd_histogram,
        calculated_at  = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN
      INSERT (symbol, date, macd, macd_signal, macd_histogram, calculated_at)
      VALUES (S.symbol, S.date, S.macd, S.macd_signal, S.macd_histogram, CURRENT_TIMESTAMP());

    SET v_rows_merged = @@row_count;

    DROP TABLE IF EXISTS temp_macd_numbered;
    DROP TABLE IF EXISTS temp_signal;

    SET v_finished_at = CURRENT_TIMESTAMP();
    CALL `YOUR_PROJECT_ID.market_data.sp_write_audit_log`(
      v_run_id,
      'sp_macd',
      v_started_at,
      v_finished_at,
      v_rows_merged,
      'success',
      CAST(NULL AS STRING)
    );
  EXCEPTION WHEN ERROR THEN
    SET v_finished_at = CURRENT_TIMESTAMP();
    CALL `YOUR_PROJECT_ID.market_data.sp_write_audit_log`(
      v_run_id,
      'sp_macd',
      v_started_at,
      v_finished_at,
      CAST(NULL AS INT64),
      'error',
      @@error.message
    );
    RAISE;
  END;
END;

-- Stored Procedure: sp_rsi
--
-- Calculates 14-period RSI (Relative Strength Index) for all symbols.
--
-- RSI formula:
--   1. Daily change = close - previous close   (LAG window function)
--   2. Gain = change if positive, else 0
--   3. Loss = |change| if negative, else 0
--   4. Avg Gain / Avg Loss over 14 periods     (sliding window AVG)
--   5. RS  = avg_gain / avg_loss
--   6. RSI = 100 − (100 / (1 + RS))
--
-- Note: This uses Cutler's RSI (simple average), which is a close
-- approximation to Wilder's RSI (which uses exponential smoothing).
-- Both are valid; Wilder's is more common in trading platforms.

CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_rsi`(v_run_id STRING)
BEGIN
  DECLARE v_started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_finished_at TIMESTAMP;
  DECLARE v_rows_merged INT64 DEFAULT 0;

  BEGIN
    MERGE `YOUR_PROJECT_ID.market_data.technical_indicators` AS T
    USING (
      WITH
      -- Step 1: calculate daily price changes using LAG (look at previous row)
      price_changes AS (
        SELECT
          symbol,
          date,
          close - LAG(close) OVER (PARTITION BY symbol ORDER BY date) AS daily_change
        FROM `YOUR_PROJECT_ID.market_data.raw_prices`
      ),

      -- Step 2: split changes into gains and losses
      gains_losses AS (
        SELECT
          symbol,
          date,
          GREATEST(daily_change, 0)  AS gain,   -- positive moves only
          GREATEST(-daily_change, 0) AS loss    -- negative moves (as positive value)
        FROM price_changes
        WHERE daily_change IS NOT NULL           -- first row has no previous — skip it
      ),

      -- Step 3: 14-period rolling average of gains and losses
      avg_gl AS (
        SELECT
          symbol,
          date,
          AVG(gain) OVER (
            PARTITION BY symbol ORDER BY date
            ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
          ) AS avg_gain,
          AVG(loss) OVER (
            PARTITION BY symbol ORDER BY date
            ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
          ) AS avg_loss
        FROM gains_losses
      )

      -- Step 4: apply RSI formula
      SELECT
        symbol,
        date,
        ROUND(
          CASE
            WHEN avg_loss = 0 THEN 100.0        -- all gains, no losses → RSI = 100
            ELSE 100 - (100 / (1 + avg_gain / avg_loss))
          END,
          2
        ) AS rsi_14
      FROM avg_gl

    ) AS S
    ON T.symbol = S.symbol AND T.date = S.date
    WHEN MATCHED THEN
      UPDATE SET
        rsi_14        = S.rsi_14,
        calculated_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN
      INSERT (symbol, date, rsi_14, calculated_at)
      VALUES (S.symbol, S.date, S.rsi_14, CURRENT_TIMESTAMP());

    SET v_rows_merged = @@row_count;
    SET v_finished_at = CURRENT_TIMESTAMP();
    CALL `YOUR_PROJECT_ID.market_data.sp_write_audit_log`(
      v_run_id,
      'sp_rsi',
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
      'sp_rsi',
      v_started_at,
      v_finished_at,
      CAST(NULL AS INT64),
      'error',
      @@error.message
    );
    RAISE;
  END;
END;

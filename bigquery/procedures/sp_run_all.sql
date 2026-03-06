-- Stored Procedure: sp_run_all
--
-- Orchestrator — calls all indicator procedures in the correct order.
-- This is the single entrypoint called after every ingestion run.
--
-- Order matters:
--   1. sp_moving_averages  → populates ema_12, ema_26 (needed by sp_macd)
--   2. sp_rsi              → independent, can run in any order
--   3. sp_macd             → reads ema_12/ema_26, must run after step 1
--   4. sp_bollinger_bands  → independent
--
-- Usage:
--   CALL `YOUR_PROJECT_ID.market_data.sp_run_all`();

-- Orchestrator
CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_run_all`()
BEGIN
  DECLARE v_run_id STRING DEFAULT GENERATE_UUID();
  DECLARE v_started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_finished_at TIMESTAMP;
  DECLARE v_failed_procedures ARRAY<STRING> DEFAULT [];

  -- 1) moving averages
  BEGIN
    CALL `YOUR_PROJECT_ID.market_data.sp_moving_averages`(v_run_id);
  EXCEPTION WHEN ERROR THEN
    SET v_failed_procedures = ARRAY_CONCAT(v_failed_procedures, ['sp_moving_averages']);
  END;

  -- 2) rsi
  BEGIN
    CALL `YOUR_PROJECT_ID.market_data.sp_rsi`(v_run_id);
  EXCEPTION WHEN ERROR THEN
    SET v_failed_procedures = ARRAY_CONCAT(v_failed_procedures, ['sp_rsi']);
  END;

  -- 3) macd (depends on EMA from step 1)
  BEGIN
    CALL `YOUR_PROJECT_ID.market_data.sp_macd`(v_run_id);
  EXCEPTION WHEN ERROR THEN
    SET v_failed_procedures = ARRAY_CONCAT(v_failed_procedures, ['sp_macd']);
  END;

  -- 4) bollinger bands
  BEGIN
    CALL `YOUR_PROJECT_ID.market_data.sp_bollinger_bands`(v_run_id);
  EXCEPTION WHEN ERROR THEN
    SET v_failed_procedures = ARRAY_CONCAT(v_failed_procedures, ['sp_bollinger_bands']);
  END;

  SET v_finished_at = CURRENT_TIMESTAMP();
  CALL `YOUR_PROJECT_ID.market_data.sp_write_audit_log`(
    v_run_id,
    'sp_run_all',
    v_started_at,
    v_finished_at,
    CAST(NULL AS INT64),
    IF(ARRAY_LENGTH(v_failed_procedures) = 0, 'success', 'error'),
    IF(
      ARRAY_LENGTH(v_failed_procedures) = 0,
      CAST(NULL AS STRING),
      CONCAT('Failed child procedures: ', ARRAY_TO_STRING(v_failed_procedures, ', '))
    )
  );
END;

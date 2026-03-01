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

CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_run_all`()
BEGIN

  CALL `YOUR_PROJECT_ID.market_data.sp_moving_averages`();
  CALL `YOUR_PROJECT_ID.market_data.sp_rsi`();
  CALL `YOUR_PROJECT_ID.market_data.sp_macd`();        -- depends on EMA from step 1
  CALL `YOUR_PROJECT_ID.market_data.sp_bollinger_bands`();

END;

-- Stored Procedure: sp_write_audit_log
--
-- Shared audit logger for all indicator/orchestrator procedures.

CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_write_audit_log`(
  v_run_id STRING,
  v_procedure_name STRING,
  v_started_at TIMESTAMP,
  v_finished_at TIMESTAMP,
  v_rows_merged INT64,
  v_status STRING,
  v_error_message STRING
)
BEGIN
  INSERT INTO `YOUR_PROJECT_ID.market_data.procedure_audit_log` (
    run_id,
    procedure_name,
    started_at,
    finished_at,
    duration_seconds,
    rows_merged,
    status,
    error_message
  )
  VALUES (
    v_run_id,
    v_procedure_name,
    v_started_at,
    v_finished_at,
    CAST(TIMESTAMP_DIFF(v_finished_at, v_started_at, MILLISECOND) AS FLOAT64) / 1000.0,
    v_rows_merged,
    v_status,
    v_error_message
  );
END;

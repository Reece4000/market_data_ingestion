CREATE TABLE IF NOT EXISTS `cobalt-list-484922-h9.market_data.audit_log` (
  run_id STRING,
  procedure_name STRING,
  started_at TIMESTAMP,
  finished_at TIMESTAMP,
  duration_seconds FLOAT64,
  rows_merged INT64,
  status STRING,
  error_message STRING
) PARTITION BY DATE(started_at);
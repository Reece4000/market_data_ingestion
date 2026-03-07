-- Stored Procedure: sp_data_quality
--
-- Runs non-blocking data quality checks against raw_prices and writes findings to
-- data_quality_report. This procedure logs audit status but intentionally does not
-- raise on error so indicator procedures can continue.

CREATE OR REPLACE PROCEDURE `YOUR_PROJECT_ID.market_data.sp_data_quality`(v_run_id STRING)
BEGIN
  DECLARE v_started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_finished_at TIMESTAMP;
  DECLARE v_rows_logged INT64 DEFAULT 0;

  BEGIN
    INSERT INTO `YOUR_PROJECT_ID.market_data.data_quality_report` (
      run_id,
      checked_at,
      symbol,
      check_name,
      severity,
      affected_date,
      detail
    )
    WITH
    symbol_bounds AS (
      SELECT symbol, MIN(date) AS min_date, MAX(date) AS max_date
      FROM `YOUR_PROJECT_ID.market_data.raw_prices`
      GROUP BY symbol
    ),
    expected_trading_days AS (
      SELECT
        b.symbol,
        d AS date
      FROM symbol_bounds b,
      UNNEST(GENERATE_DATE_ARRAY(b.min_date, b.max_date)) AS d
      WHERE EXTRACT(DAYOFWEEK FROM d) BETWEEN 2 AND 6
    ),
    missing_days AS (
      SELECT
        e.symbol,
        e.date AS missing_date
      FROM expected_trading_days e
      LEFT JOIN `YOUR_PROJECT_ID.market_data.raw_prices` r
        ON r.symbol = e.symbol
       AND r.date = e.date
      WHERE r.date IS NULL
    ),
    missing_day_groups AS (
      SELECT
        symbol,
        missing_date,
        DATE_SUB(
          missing_date,
          INTERVAL ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY missing_date) DAY
        ) AS gap_group
      FROM missing_days
    ),
    gap_alerts AS (
      SELECT
        symbol,
        'missing_date_gap' AS check_name,
        'critical' AS severity,
        MIN(missing_date) AS affected_date,
        CONCAT(
          'Missing trading dates from ',
          CAST(MIN(missing_date) AS STRING),
          ' to ',
          CAST(MAX(missing_date) AS STRING),
          ' (',
          CAST(COUNT(*) AS STRING),
          ' consecutive days)'
        ) AS detail
      FROM missing_day_groups
      GROUP BY symbol, gap_group
      HAVING COUNT(*) > 3
    ),
    price_anomaly_alerts AS (
      SELECT
        symbol,
        'price_anomaly' AS check_name,
        'critical' AS severity,
        date AS affected_date,
        CONCAT(
          'close=',
          CAST(close AS STRING),
          ', high=',
          CAST(high AS STRING),
          ', low=',
          CAST(low AS STRING)
        ) AS detail
      FROM `YOUR_PROJECT_ID.market_data.raw_prices`
      WHERE close <= 0
         OR high < low
         OR close > high * 1.5
    ),
    stale_data_alerts AS (
      SELECT
        symbol,
        'stale_data' AS check_name,
        'critical' AS severity,
        latest_date AS affected_date,
        CONCAT(
          'Latest row is ',
          CAST(DATE_DIFF(CURRENT_DATE(), latest_date, DAY) AS STRING),
          ' days behind current_date'
        ) AS detail
      FROM (
        SELECT symbol, MAX(date) AS latest_date
        FROM `YOUR_PROJECT_ID.market_data.raw_prices`
        GROUP BY symbol
      )
      WHERE DATE_DIFF(CURRENT_DATE(), latest_date, DAY) > 2
    ),
    volume_window AS (
      SELECT
        symbol,
        date,
        volume,
        AVG(volume) OVER (
          PARTITION BY symbol
          ORDER BY date
          ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS avg_vol_20,
        COUNT(volume) OVER (
          PARTITION BY symbol
          ORDER BY date
          ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS sample_size
      FROM `YOUR_PROJECT_ID.market_data.raw_prices`
    ),
    volume_spike_alerts AS (
      SELECT
        symbol,
        'volume_spike' AS check_name,
        'warning' AS severity,
        date AS affected_date,
        CONCAT(
          'volume=',
          CAST(volume AS STRING),
          ', avg_20d=',
          CAST(ROUND(avg_vol_20, 2) AS STRING)
        ) AS detail
      FROM volume_window
      WHERE sample_size >= 20
        AND avg_vol_20 > 0
        AND volume > 10 * avg_vol_20
    )
    SELECT
      v_run_id AS run_id,
      CURRENT_TIMESTAMP() AS checked_at,
      symbol,
      check_name,
      severity,
      affected_date,
      detail
    FROM (
      SELECT * FROM gap_alerts
      UNION ALL
      SELECT * FROM price_anomaly_alerts
      UNION ALL
      SELECT * FROM stale_data_alerts
      UNION ALL
      SELECT * FROM volume_spike_alerts
    );

    SET v_rows_logged = @@row_count;
    SET v_finished_at = CURRENT_TIMESTAMP();
    CALL `YOUR_PROJECT_ID.market_data.sp_write_audit_log`(
      v_run_id,
      'sp_data_quality',
      v_started_at,
      v_finished_at,
      v_rows_logged,
      'success',
      CAST(NULL AS STRING)
    );
  EXCEPTION WHEN ERROR THEN
    SET v_finished_at = CURRENT_TIMESTAMP();
    CALL `YOUR_PROJECT_ID.market_data.sp_write_audit_log`(
      v_run_id,
      'sp_data_quality',
      v_started_at,
      v_finished_at,
      CAST(NULL AS INT64),
      'error',
      @@error.message
    );
  END;
END;

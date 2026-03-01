# ── Dataset ───────────────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "market_data" {
  project     = var.project_id
  dataset_id  = var.bq_dataset
  location    = var.bq_location
  description = "Raw price data and derived technical indicators"

  depends_on = [google_project_service.apis]
}

# ── Tables ────────────────────────────────────────────────────────────────────
# Partitioned by date + clustered by symbol to minimise scan cost.

resource "google_bigquery_table" "raw_prices" {
  project     = var.project_id
  dataset_id  = google_bigquery_dataset.market_data.dataset_id
  table_id    = "raw_prices"
  description = "Daily OHLCV data from Yahoo Finance and CoinGecko"

  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "date"
  }

  clustering = ["symbol"]

  schema = jsonencode([
    { name = "symbol",      type = "STRING",    mode = "REQUIRED" },
    { name = "asset_type",  type = "STRING",    mode = "REQUIRED" },
    { name = "date",        type = "DATE",      mode = "REQUIRED" },
    { name = "open",        type = "FLOAT64",   mode = "NULLABLE" },
    { name = "high",        type = "FLOAT64",   mode = "NULLABLE" },
    { name = "low",         type = "FLOAT64",   mode = "NULLABLE" },
    { name = "close",       type = "FLOAT64",   mode = "NULLABLE" },
    { name = "volume",      type = "FLOAT64",   mode = "NULLABLE" },
    { name = "ingested_at", type = "TIMESTAMP", mode = "NULLABLE" },
  ])

  # schema and partitioning were set correctly by setup.sql — prevent Terraform
  # from destroying and recreating the table if GCP's representation differs slightly.
  lifecycle {
    ignore_changes = [schema, time_partitioning, clustering]
  }
}

resource "google_bigquery_table" "technical_indicators" {
  project     = var.project_id
  dataset_id  = google_bigquery_dataset.market_data.dataset_id
  table_id    = "technical_indicators"
  description = "Technical indicators derived by stored procedures"

  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "date"
  }

  clustering = ["symbol"]

  schema = jsonencode([
    { name = "symbol",          type = "STRING",    mode = "REQUIRED" },
    { name = "date",            type = "DATE",      mode = "REQUIRED" },
    { name = "sma_20",          type = "FLOAT64",   mode = "NULLABLE" },
    { name = "sma_50",          type = "FLOAT64",   mode = "NULLABLE" },
    { name = "sma_200",         type = "FLOAT64",   mode = "NULLABLE" },
    { name = "ema_12",          type = "FLOAT64",   mode = "NULLABLE" },
    { name = "ema_26",          type = "FLOAT64",   mode = "NULLABLE" },
    { name = "rsi_14",          type = "FLOAT64",   mode = "NULLABLE" },
    { name = "macd",            type = "FLOAT64",   mode = "NULLABLE" },
    { name = "macd_signal",     type = "FLOAT64",   mode = "NULLABLE" },
    { name = "macd_histogram",  type = "FLOAT64",   mode = "NULLABLE" },
    { name = "bb_upper",        type = "FLOAT64",   mode = "NULLABLE" },
    { name = "bb_lower",        type = "FLOAT64",   mode = "NULLABLE" },
    { name = "calculated_at",   type = "TIMESTAMP", mode = "NULLABLE" },
  ])

  lifecycle {
    ignore_changes = [schema, time_partitioning, clustering]
  }
}

# ── Stored procedures ─────────────────────────────────────────────────────────
# Terraform doesn't have a clean native resource for BigQuery stored procedures,
# so we run the existing SQL files via local-exec.
# Triggers on file hash — re-runs automatically if SQL changes.

resource "null_resource" "bigquery_procedures" {
  triggers = {
    sp_moving_averages = filemd5("${path.module}/../bigquery/procedures/sp_moving_averages.sql")
    sp_rsi             = filemd5("${path.module}/../bigquery/procedures/sp_rsi.sql")
    sp_macd            = filemd5("${path.module}/../bigquery/procedures/sp_macd.sql")
    sp_bollinger_bands = filemd5("${path.module}/../bigquery/procedures/sp_bollinger_bands.sql")
    sp_run_all         = filemd5("${path.module}/../bigquery/procedures/sp_run_all.sql")
  }

  provisioner "local-exec" {
    command = <<-EOT
      for f in ${path.module}/../bigquery/procedures/*.sql; do
        echo "Applying $f..."
        sed "s/YOUR_PROJECT_ID/${var.project_id}/g" "$f" \
          | bq query --use_legacy_sql=false --project_id="${var.project_id}"
      done
    EOT
  }

  depends_on = [
    google_bigquery_dataset.market_data,
    google_bigquery_table.raw_prices,
    google_bigquery_table.technical_indicators,
  ]
}

# ── Views ─────────────────────────────────────────────────────────────────────

resource "null_resource" "bigquery_views" {
  triggers = {
    vw_latest_indicators = filemd5("${path.module}/../bigquery/views/vw_latest_indicators.sql")
  }

  provisioner "local-exec" {
    command = <<-EOT
      sed "s/YOUR_PROJECT_ID/${var.project_id}/g" \
        "${path.module}/../bigquery/views/vw_latest_indicators.sql" \
        | bq query --use_legacy_sql=false --project_id="${var.project_id}"
    EOT
  }

  depends_on = [null_resource.bigquery_procedures]
}

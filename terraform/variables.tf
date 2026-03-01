variable "project_id" {
  description = "GCP project ID (set via TF_VAR_project_id or scripts/tf_apply.sh)"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run and Scheduler"
  type        = string
  default     = "us-central1"
}

variable "bq_dataset" {
  description = "BigQuery dataset name"
  type        = string
  default     = "market_data"
}

variable "bq_location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "US"
}

variable "symbols_stock" {
  description = "Comma-separated stock tickers to ingest"
  type        = string
  default     = "AAPL,MSFT,NVDA,SPY"
}

variable "symbols_crypto" {
  description = "Comma-separated CoinGecko coin IDs to ingest"
  type        = string
  default     = "bitcoin,ethereum"
}

variable "ingestion_schedule" {
  description = "Cron schedule for the ingestion job (UTC)"
  type        = string
  default     = "0 18 * * 1-5" # 6pm UTC weekdays
}

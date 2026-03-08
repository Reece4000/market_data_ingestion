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

variable "firebase_project_id" {
  description = "Firebase project ID used for token verification"
  type        = string
}

variable "firebase_api_key" {
  description = "Firebase web app API key for frontend auth"
  type        = string
  sensitive   = true
}

variable "firebase_auth_domain" {
  description = "Firebase auth domain for frontend auth"
  type        = string
}

variable "firebase_app_id" {
  description = "Firebase web app appId for frontend auth"
  type        = string
  sensitive   = true
}

variable "api_rate_limit_per_min" {
  description = "Max API requests per minute per client IP"
  type        = number
  default     = 240
}

variable "watchlist_write_rate_limit_per_min" {
  description = "Max watchlist write requests per minute per client IP"
  type        = number
  default     = 20
}

variable "symbols_cache_ttl_seconds" {
  description = "TTL for /api/symbols in-memory cache"
  type        = number
  default     = 300
}

variable "watchlist_cache_ttl_seconds" {
  description = "TTL for /api/watchlist in-memory cache"
  type        = number
  default     = 30
}

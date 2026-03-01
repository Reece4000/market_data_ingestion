# Cloud Scheduler triggers the ingestion Cloud Run Job daily.
# The SA needs roles/run.invoker (granted in iam.tf) to call the Jobs API.

resource "google_cloud_scheduler_job" "ingestion" {
  project     = var.project_id
  region      = var.region
  name        = "market-ingestion-schedule"
  description = "Trigger market ingestion daily at 6pm UTC on weekdays"
  schedule    = var.ingestion_schedule
  time_zone   = "UTC"

  http_target {
    # Cloud Run Jobs execution endpoint
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.ingestion.name}:run"
    http_method = "POST"
    body        = base64encode("{}")

    oauth_token {
      service_account_email = google_service_account.market_prep.email
    }
  }

  depends_on = [
    google_cloud_run_v2_job.ingestion,
    google_project_service.apis,
  ]
}

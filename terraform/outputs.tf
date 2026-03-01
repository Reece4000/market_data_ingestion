output "api_url" {
  description = "Cloud Run URL for the FastAPI backend"
  value       = google_cloud_run_v2_service.api.uri
}

output "frontend_url" {
  description = "Cloud Run URL for the React frontend"
  value       = google_cloud_run_v2_service.frontend.uri
}

output "service_account_email" {
  description = "Service account used by Cloud Run and Cloud Scheduler"
  value       = google_service_account.market_prep.email
}

output "ingestion_job_name" {
  description = "Cloud Run Job name — run manually with: gcloud run jobs execute <name>"
  value       = google_cloud_run_v2_job.ingestion.name
}

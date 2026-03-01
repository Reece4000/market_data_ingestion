# Service account used by Cloud Run (API + ingestion job) and Cloud Scheduler.

resource "google_service_account" "market_prep" {
  project      = var.project_id
  account_id   = "market-prep-sa"
  display_name = "Market Prep SA"

  depends_on = [google_project_service.apis]
}

locals {
  sa_roles = [
    "roles/bigquery.dataEditor", # read/write BQ tables
    "roles/bigquery.jobUser",    # run BQ queries
    "roles/datastore.user",      # read/write Firestore
    "roles/run.invoker",         # Cloud Scheduler → trigger Cloud Run Job
  ]
}

resource "google_project_iam_member" "market_prep_roles" {
  for_each = toset(local.sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.market_prep.email}"
}

# Cloud Build service account needs permission to push images and deploy Cloud Run.
# The Cloud Build SA is created automatically when the API is enabled.
locals {
  cloudbuild_sa = "${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

data "google_project" "project" {
  project_id = var.project_id
}

resource "google_project_iam_member" "cloudbuild_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${local.cloudbuild_sa}"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "cloudbuild_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${local.cloudbuild_sa}"

  depends_on = [google_project_service.apis]
}

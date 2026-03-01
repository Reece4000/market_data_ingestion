# ── Build images ──────────────────────────────────────────────────────────────
# null_resource triggers a rebuild only when the source files change.
# Uses gcloud builds submit (Cloud Build) for ingestion + API,
# and docker build + push for the frontend (needs --build-arg at build time).

resource "null_resource" "build_ingestion" {
  triggers = {
    src = sha1(join("", [for f in sort(fileset("${path.module}/../ingestion", "**")) : filesha1("${path.module}/../ingestion/${f}")]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud builds submit ${path.module}/../ingestion \
        --tag gcr.io/${var.project_id}/market-ingestion \
        --project ${var.project_id}
    EOT
  }

  depends_on = [google_project_service.apis]
}

resource "null_resource" "build_api" {
  triggers = {
    src = sha1(join("", [for f in sort(fileset("${path.module}/../api", "**")) : filesha1("${path.module}/../api/${f}")]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud builds submit ${path.module}/../api \
        --tag gcr.io/${var.project_id}/market-api \
        --project ${var.project_id}
    EOT
  }

  depends_on = [google_project_service.apis]
}

# Frontend is built after the API is deployed so we can bake its URL in.
resource "null_resource" "build_frontend" {
  triggers = {
    src     = sha1(join("", [for f in sort(fileset("${path.module}/../frontend", "**")) : filesha1("${path.module}/../frontend/${f}")]))
    api_url = google_cloud_run_v2_service.api.uri
  }

  # Use Cloud Build (native AMD64) instead of local docker build,
  # which avoids broken emulated binaries on Apple Silicon.
  provisioner "local-exec" {
    command = <<-EOT
      gcloud builds submit ${path.module}/../frontend \
        --config=${path.module}/../frontend/cloudbuild.yaml \
        --substitutions=_VITE_API_URL=${google_cloud_run_v2_service.api.uri} \
        --project=${var.project_id}
    EOT
  }

  depends_on = [google_cloud_run_v2_service.api]
}

# ── Cloud Run Job — Ingestion ─────────────────────────────────────────────────
# Runs to completion (not a persistent service).
# Triggered daily by Cloud Scheduler.

resource "google_cloud_run_v2_job" "ingestion" {
  project  = var.project_id
  name     = "market-ingestion"
  location = var.region

  template {
    template {
      service_account = google_service_account.market_prep.email

      containers {
        image = "gcr.io/${var.project_id}/market-ingestion"

        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "BQ_DATASET"
          value = var.bq_dataset
        }
        env {
          name  = "SYMBOLS_STOCK"
          value = var.symbols_stock
        }
        env {
          name  = "SYMBOLS_CRYPTO"
          value = var.symbols_crypto
        }
      }
    }
  }

  depends_on = [
    null_resource.build_ingestion,
    google_project_iam_member.market_prep_roles,
  ]
}

# ── Cloud Run Service — API ───────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "api" {
  project  = var.project_id
  name     = "market-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.market_prep.email

    containers {
      image = "gcr.io/${var.project_id}/market-api"

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "BQ_DATASET"
        value = var.bq_dataset
      }
    }
  }

  depends_on = [
    null_resource.build_api,
    google_project_iam_member.market_prep_roles,
    google_bigquery_dataset.market_data,
  ]
}

# Allow unauthenticated requests to the API (public read-only data).
resource "google_cloud_run_v2_service_iam_member" "api_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ── Cloud Run Service — Frontend ──────────────────────────────────────────────

resource "google_cloud_run_v2_service" "frontend" {
  project  = var.project_id
  name     = "market-frontend"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "gcr.io/${var.project_id}/market-frontend"

      # nginx listens on 80; tell Cloud Run which port to route to
      ports {
        container_port = 80
      }
    }
  }

  depends_on = [null_resource.build_frontend]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

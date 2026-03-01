terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # State is stored locally by default.
  # terraform.tfstate is gitignored — don't commit it.
  # For a shared/production setup, use a GCS backend:
  #
  # backend "gcs" {
  #   bucket = "your-tf-state-bucket"
  #   prefix = "market-prep"
  # }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = file("${path.module}/../sa-key.json")
}

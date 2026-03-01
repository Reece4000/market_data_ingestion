# Firestore in Native mode — required for the watchlist API.
# Must be in Native mode (not Datastore mode) for document/collection API.
# nam5 = North America multi-region (us-central).

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.apis]
}

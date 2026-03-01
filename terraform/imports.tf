# This file is intentionally empty.
#
# Import blocks were used here during initial migration to bring resources
# that were created by the old shell scripts into Terraform state.
# They have been removed once successfully applied — leaving them in place
# causes `terraform apply` to fail on fresh projects where the resources
# don't yet exist.
#
# If you ever need to re-adopt an out-of-band resource, add a block here
# temporarily, run `terraform apply`, then remove it again. Example:
#
# import {
#   id = "your-project/market_data"
#   to = google_bigquery_dataset.market_data
# }

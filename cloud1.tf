locals {
  project2 = "my-project-name1" # Google Cloud Platform Project ID
}

resource "google_service_account" "account2" {
  account_id   = "gcf-sa"
  display_name = "Test Service Account"
}

resource "google_storage_bucket" "bucket2" {
  name                        = "${local.project}-gcf-source"  # Every bucket name must be globally unique
  location                    = "US"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "object2" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = "function-source.zip"  # Add path to the zipped function source code
}

resource "google_cloudfunctions2_function" "function2" {
  name        = "gcf-function" # name should use kebab-case so generated Cloud Run service name will be the same
  location    = "us-central1"
  description = "a new function"

  build_config {
    runtime     = "nodejs16"
    entry_point = "helloHttp"  # Set the entry point
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    min_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.account.email
  }
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = google_cloudfunctions2_function.function.project
  location       = google_cloudfunctions2_function.function.location
  cloud_function = google_cloudfunctions2_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.account.email}"
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  project  = google_cloudfunctions2_function.function.project
  location = google_cloudfunctions2_function.function.location
  service  = google_cloudfunctions2_function.function.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.account.email}"
}

resource "google_cloud_scheduler_job" "invoke_cloud_function" {
  name        = "invoke-gcf-function"
  description = "Schedule the HTTPS trigger for cloud function"
  schedule    = "0 0 * * *" # every day at midnight
  project     = google_cloudfunctions2_function.function.project
  region      = google_cloudfunctions2_function.function.location

  http_target {
    uri         = google_cloudfunctions2_function.function.service_config[0].uri
    http_method = "POST"
    oidc_token {
      audience              = "${google_cloudfunctions2_function.function.service_config[0].uri}/"
      service_account_email = google_service_account.account.email
    }
  }
}

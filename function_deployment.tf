# Packages the ingestion python script into a zip
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/ingestion"
  output_path = "${path.module}/ingestion.zip"
}

# Stores the zip in GCS
resource "google_storage_bucket" "function_code" {
  name          = "${var.hub_project_id}-ingestion-code"
  location      = var.region
  force_destroy = true
}

resource "google_storage_bucket_object" "code_zip" {
  name   = "ingestion-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_code.name
  source = data.archive_file.function_source.output_path
}

# 2nd Gen Cloud Function (Runs natively on Cloud Run)
resource "google_cloudfunctions2_function" "metrics_ingestion" {
  name        = "datacommons-health-ingest-v2"
  location    = var.region
  description = "Ingests Data Commons Cloud Monitoring metrics into BigQuery"

  build_config {
    runtime     = "python310"
    entry_point = "fetch_and_write_metrics"

    source {
      storage_source {
        bucket = google_storage_bucket.function_code.name
        object = google_storage_bucket_object.code_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60

    environment_variables = {
      PROJECT_ID = var.hub_project_id
    }
  }
}

# Cloud Scheduler to run it daily at 1 AM
resource "google_cloud_scheduler_job" "daily_ingestion" {
  name             = "daily-metrics-ingestion"
  description      = "Triggers the metrics ingestion function once a day"
  schedule         = "0 1 * * *"
  time_zone        = "America/Los_Angeles"
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions2_function.metrics_ingestion.service_config[0].uri
    
    # We use OIDC routing for secure service-to-service communication
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
}

# Create a dedicated Service Account for the Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "health-scheduler-sa"
  display_name = "Cloud Scheduler SA for Health Metrics"
}

# Grant the Scheduler SA permission to invoke the Cloud Run function
resource "google_cloud_run_service_iam_member" "invoker" {
  project  = google_cloudfunctions2_function.metrics_ingestion.project
  location = google_cloudfunctions2_function.metrics_ingestion.location
  service  = google_cloudfunctions2_function.metrics_ingestion.name
  
  role   = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

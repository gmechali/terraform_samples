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

# 1st Gen Cloud Function
resource "google_cloudfunctions_function" "metrics_ingestion" {
  name        = "datacommons-health-ingestion"
  description = "Ingests Data Commons Cloud Monitoring metrics into BigQuery"
  runtime     = "python310"

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_code.name
  source_archive_object = google_storage_bucket_object.code_zip.name
  trigger_http          = true
  entry_point           = "fetch_and_write_metrics"
  
  environment_variables = {
    PROJECT_ID = var.hub_project_id
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
    uri         = google_cloudfunctions_function.metrics_ingestion.https_trigger_url
  }
}

# Allow unauthenticated invocations so the Scheduler can trigger it easily
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.metrics_ingestion.project
  region         = google_cloudfunctions_function.metrics_ingestion.region
  cloud_function = google_cloudfunctions_function.metrics_ingestion.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

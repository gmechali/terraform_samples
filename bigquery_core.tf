# 1. Central BigQuery Dataset
resource "google_bigquery_dataset" "health_metrics" {
  dataset_id    = "oncall_health"
  friendly_name = "On-call Health Metrics"
  description   = "Central dataset for Data Commons service health and on-call metrics"
  location      = var.region

  # Ensure we can delete this during testing / tear down (No Deletion Protection)
  delete_contents_on_destroy = true
}

# Define the Raw Metrics Table schema
resource "google_bigquery_table" "raw_metrics_table" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "raw_metrics"
  
  # Allow easy teardown for testing
  deletion_protection = false

  schema = <<EOF
[
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "target_date",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "project_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "service_name",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "archetype",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "availability_ratio",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "total_requests",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "error_5xx_requests",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "error_4xx_requests",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "total_errors",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "latency_p50_ms",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "latency_p95_ms",
    "type": "FLOAT",
    "mode": "NULLABLE"
  }
]
EOF
}

# 4a. Native Raw Tables for Cloud Build & Cloud Deploy
resource "google_bigquery_table" "cloud_build_raw" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "cloud_builds_raw"
  project    = var.hub_project_id
  deletion_protection = false

  schema = <<EOF
[
  {"name": "subscription_name", "type": "STRING", "mode": "NULLABLE"},
  {"name": "message_id", "type": "STRING", "mode": "NULLABLE"},
  {"name": "publish_time", "type": "TIMESTAMP", "mode": "NULLABLE"},
  {"name": "data", "type": "STRING", "mode": "NULLABLE"},
  {"name": "attributes", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

resource "google_bigquery_table" "cloud_deploy_raw" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "cloud_deploy_raw"
  project    = var.hub_project_id
  deletion_protection = false

  schema = <<EOF
[
  {"name": "subscription_name", "type": "STRING", "mode": "NULLABLE"},
  {"name": "message_id", "type": "STRING", "mode": "NULLABLE"},
  {"name": "publish_time", "type": "TIMESTAMP", "mode": "NULLABLE"},
  {"name": "data", "type": "STRING", "mode": "NULLABLE"},
  {"name": "attributes", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

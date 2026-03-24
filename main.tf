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
    "name": "error_requests",
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

# 2. Project-Level Log Sink (Since you don't have Org-level IAM)
resource "google_logging_project_sink" "error_sink_project" {
  name        = "datacommons-health-project-sink"
  project     = var.hub_project_id
  destination = "bigquery.googleapis.com/projects/${var.hub_project_id}/datasets/${google_bigquery_dataset.health_metrics.dataset_id}"
  filter      = "labels.\"datacommons-service\" : * AND severity >= WARNING"
}

resource "google_project_iam_member" "sink_bq_writer" {
  project = var.hub_project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.error_sink_project.writer_identity
}

# 3. Multi-Project Metrics Scope for Cloud Monitoring
# The Hub project becomes a scoping project that can view Spoke projects
resource "google_monitoring_monitored_project" "spoke_projects" {
  for_each      = toset(var.spoke_project_ids)
  metrics_scope = "locations/global/metricsScopes/${var.hub_project_id}"
  name          = each.value
}

# 4. Central Pub/Sub Topic for Deployments
resource "google_pubsub_topic" "deployment_events" {
  name = "datacommons-deployment-events"
}

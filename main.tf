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



data "google_project" "hub_project" {
  project_id = var.hub_project_id
}

resource "google_project_iam_member" "pubsub_bq_writer" {
  project = var.hub_project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:service-${data.google_project.hub_project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
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

# 4b. System Topics (Forced creation in case pipelines haven't run yet)
# TODO: When moving this Terraform to your actual CI/CD project, you MUST DELETE these two 
# google_pubsub_topic blocks below, because GCP will have already created them natively!
# (Also revert the topic references in the subscriptions to use the raw "projects/.../topics/..." string).
# resource "google_pubsub_topic" "cloud_build_topic" {
#   name    = "cloud-builds"
#   project = var.hub_project_id
# }

# resource "google_pubsub_topic" "cloud_deploy_topic" {
#   name    = "clouddeploy-operations"
#   project = var.hub_project_id
# }

# 4c. Native Subscriptions pulling system topics
resource "google_pubsub_subscription" "cloud_builds_bq_sub" {
 name  = "cloud-builds-bq-sub"
 topic = "projects/${var.hub_project_id}/topics/cloud-builds"

 bigquery_config {
   table          = "${var.hub_project_id}.${google_bigquery_dataset.health_metrics.dataset_id}.${google_bigquery_table.cloud_build_raw.table_id}"
   write_metadata = true
 }

 depends_on = [google_project_iam_member.pubsub_bq_writer]
}

# Force create clouddeploy-operations since GCP failed to do it automatically in this project
resource "google_pubsub_topic" "cloud_deploy_topic" {
  name    = "clouddeploy-operations"
  project = var.hub_project_id
}

resource "google_pubsub_subscription" "cloud_deploy_bq_sub" {
  name  = "clouddeploy-bq-sub"
  topic = google_pubsub_topic.cloud_deploy_topic.id

  bigquery_config {
    table          = "${var.hub_project_id}.${google_bigquery_dataset.health_metrics.dataset_id}.${google_bigquery_table.cloud_deploy_raw.table_id}"
    write_metadata = true
  }

  depends_on = [google_project_iam_member.pubsub_bq_writer]
}

# 4d. Unified Deployment Events View
resource "google_bigquery_table" "deployment_events_raw_view" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "deployment_events_raw"
  project    = var.hub_project_id
  deletion_protection = false

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/deployment_events_raw.sql", {
      hub_project_id = var.hub_project_id
      dataset_id     = google_bigquery_dataset.health_metrics.dataset_id
    })
  }

  depends_on = [
    google_bigquery_table.cloud_build_raw,
    google_bigquery_table.cloud_deploy_raw
  ]
}

# 5. Service Performance Scores View (Category 1)
resource "google_bigquery_table" "service_performance_scores_view" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "service_performance_scores"
  project    = var.hub_project_id

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/service_performance_scores.sql", {
      hub_project_id = var.hub_project_id
      dataset_id     = google_bigquery_dataset.health_metrics.dataset_id
      table_id       = google_bigquery_table.raw_metrics_table.table_id
    })
  }

  deletion_protection = false
}

# 6. Category 3: Observability Google Sheet (External Table)
resource "google_bigquery_table" "observability_survey_sheet" {
  count      = var.observability_sheet_url != "" ? 1 : 0
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "observability_survey_sheet"
  project    = var.hub_project_id

  external_data_configuration {
    autodetect    = false
    source_format = "GOOGLE_SHEETS"
    source_uris   = [var.observability_sheet_url]
    
    google_sheets_options {
      skip_leading_rows = 2
    }
  }

  schema = <<EOF
[
  {"name": "service_name", "type": "STRING"},
  {"name": "has_staging", "type": "STRING"},
  {"name": "has_sanity_tests", "type": "STRING"},
  {"name": "has_test_coverage", "type": "STRING"},
  {"name": "has_routing_rule", "type": "STRING"},
  {"name": "has_runbook", "type": "STRING"},
  {"name": "has_error_signal", "type": "STRING"},
  {"name": "has_blackbox_prober", "type": "STRING"},
  {"name": "has_latency_threshold", "type": "STRING"},
  {"name": "has_staleness_alert", "type": "STRING"},
  {"name": "has_silent_failure_monitor", "type": "STRING"},
  {"name": "has_feature_flags", "type": "STRING"}
]
EOF
  
  deletion_protection = false
}

# 7. Category 3: Observability Scores View
resource "google_bigquery_table" "observability_scores_view" {
  count      = var.observability_sheet_url != "" ? 1 : 0
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "observability_scores"
  project    = var.hub_project_id

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/observability_scores.sql", {
      hub_project_id = var.hub_project_id
      dataset_id     = google_bigquery_dataset.health_metrics.dataset_id
      table_id       = google_bigquery_table.observability_survey_sheet[0].table_id
    })
  }

  deletion_protection = false
}

# 7b. Category 2: Pipeline Robustness Scores View
resource "google_bigquery_table" "pipeline_robustness_scores_view" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "pipeline_robustness_scores"
  project    = var.hub_project_id

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/pipeline_robustness_scores.sql", {
      hub_project_id = var.hub_project_id
      dataset_id     = google_bigquery_dataset.health_metrics.dataset_id
    })
  }

  depends_on = [
    google_bigquery_table.deployment_events_raw_view,
    google_bigquery_table.service_performance_scores_view
  ]

  deletion_protection = false
}

# 8. Final Composite Service Health Score View
resource "google_bigquery_table" "composite_health_scores_view" {
  count      = var.observability_sheet_url != "" ? 1 : 0
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "composite_health_scores"
  project    = var.hub_project_id

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/composite_health_scores.sql", {
      hub_project_id = var.hub_project_id
      dataset_id     = google_bigquery_dataset.health_metrics.dataset_id
    })
  }
  
  depends_on = [
    google_bigquery_table.service_performance_scores_view,
    google_bigquery_table.observability_scores_view,
    google_bigquery_table.pipeline_robustness_scores_view
  ]

  deletion_protection = false
}

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

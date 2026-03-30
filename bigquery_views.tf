# 4. Central Environment Classifier (UDF)
resource "google_bigquery_routine" "get_environment" {
  dataset_id      = google_bigquery_dataset.health_metrics.dataset_id
  routine_id      = "get_environment"
  routine_type    = "SCALAR_FUNCTION"
  language        = "SQL"
  
  arguments {
    name      = "service_name_input"
    data_type = "{\"typeKind\" :  \"STRING\"}"
  }
  
  return_type = "{\"typeKind\" :  \"STRING\"}"

  definition_body = <<-EOS
    CASE
      WHEN REGEXP_CONTAINS(service_name_input, r"(?i)prod") THEN "Prod"
      WHEN REGEXP_CONTAINS(service_name_input, r"(?i)--api\.datacommons\.org") THEN "Prod"
      WHEN REGEXP_CONTAINS(service_name_input, r"(?i)autorater") THEN "Prod"
      WHEN REGEXP_CONTAINS(service_name_input, r"(?i)staging") THEN "Staging"
      WHEN REGEXP_CONTAINS(service_name_input, r"(?i)autopush") THEN "Autopush"
      WHEN REGEXP_CONTAINS(service_name_input, r"(?i)dev") THEN "Dev"
      ELSE "Unknown"
    END
  EOS
}

# 4d. Unified Deployment Events View
resource "google_bigquery_table" "deployment_events_raw_view" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "deployment_events_raw"
  project    = var.hub_project_id
  deletion_protection = false

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/sql/deployment_events_raw.sql", {
      hub_project_id = var.hub_project_id
      dataset_id     = google_bigquery_dataset.health_metrics.dataset_id
    })
  }

  depends_on = [
    google_bigquery_table.cloud_build_raw,
    google_bigquery_table.cloud_deploy_raw,
    google_bigquery_routine.get_environment
  ]
}

# 5. Service Performance Scores View (Category 1)
resource "google_bigquery_table" "service_performance_scores_view" {
  dataset_id = google_bigquery_dataset.health_metrics.dataset_id
  table_id   = "service_performance_scores"
  project    = var.hub_project_id

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/sql/service_performance_scores.sql", {
      hub_project_id = var.hub_project_id
      dataset_id     = google_bigquery_dataset.health_metrics.dataset_id
      table_id       = google_bigquery_table.raw_metrics_table.table_id
    })
  }

  deletion_protection = false

  depends_on = [
    google_bigquery_routine.get_environment
  ]
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
    query          = templatefile("${path.module}/sql/observability_scores.sql", {
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
    query          = templatefile("${path.module}/sql/pipeline_robustness_scores.sql", {
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
    query          = templatefile("${path.module}/sql/composite_health_scores.sql", {
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

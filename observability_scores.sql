SELECT
  service_name,
  -- Calculate boolean TRUE string representations into ints (1 or 0)
  -- The math sums the 'true' answers and divides by 8.0, yielding the 0.0 - 1.0 Observability Score
  (
    IF(LOWER(CAST(has_staging AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_sanity_tests AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_test_coverage AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_routing_rule AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_runbook AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_error_signal AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_blackbox_prober AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_latency_threshold AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_staleness_alert AS STRING)) = 'true', 1, 0) +
    IF(LOWER(CAST(has_silent_failure_monitor AS STRING)) = 'true', 1, 0)
  ) / 8.0 * 100.0 AS observability_score
FROM `${hub_project_id}.${dataset_id}.${table_id}`

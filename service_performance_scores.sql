SELECT
  target_date,
  service_name,
  project_id,
  archetype,
  CASE
    WHEN REGEXP_CONTAINS(service_name, r"(?i)prod") THEN "Prod"
    WHEN REGEXP_CONTAINS(service_name, r"(?i)api\.datacommons\.org") THEN "Prod"
    WHEN REGEXP_CONTAINS(service_name, r"(?i)autorater") THEN "Prod"
    WHEN REGEXP_CONTAINS(service_name, r"(?i)staging") THEN "Staging"
    WHEN REGEXP_CONTAINS(service_name, r"(?i)autopush") THEN "Autopush"
    WHEN REGEXP_CONTAINS(service_name, r"(?i)dev") THEN "Dev"
    ELSE "Unknown"
  END AS environment,
  availability_ratio,
  latency_p50_ms,
  latency_p95_ms,
  total_requests,
  error_requests,
  500.0 as p50_target_ms,
  2500.0 as p95_target_ms,
  
  -- Performance Score: 65% Availability (Bounded Decay: 99% = 0 pts) + 5% P50 Latency + 20% P95 Latency + 10% Log Health (Placeholder 1.0)
  (
    (GREATEST(0.0, 1.0 - ((1.0 - availability_ratio) * 100.0)) * 0.65) + 
    (
      IF(latency_p50_ms IS NULL, 1.0, 
        IF(latency_p50_ms < 500.0, 1.0, (500.0 / latency_p50_ms))
      ) * 0.05
    ) + 
    (
      IF(latency_p95_ms IS NULL, 1.0, 
        IF(latency_p95_ms < 2500.0, 1.0, (2500.0 / latency_p95_ms))
      ) * 0.20
    ) + 
    (1.0 * 0.10)
  ) * 100.0 AS performance_score

FROM `${hub_project_id}.${dataset_id}.${table_id}`

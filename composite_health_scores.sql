SELECT
  r.target_date,
  r.project_id,
  r.service_name,
  r.archetype,
  r.environment,
  
  -- Category 1: Runtime Performance metrics
  r.availability_ratio,
  r.latency_p50_ms,
  r.latency_p95_ms,
  r.total_requests,
  r.error_requests,
  r.p50_target_ms,
  r.p95_target_ms,
  r.performance_score AS cat1_performance_score,
  
  -- Category 3: Observability Score
  -- We COALESCE to 0.0 in case a service hasn't been added to the Google Sheet yet
  COALESCE(o.observability_score, 0.0) AS cat3_observability_score,
  
  -- Category 2: Pipeline Robustness (Placeholder 100.0 until Phase 2 is implemented)
  100.0 AS cat2_pipeline_score,
  
  -- FINAL COMPOSITE SERVICE HEALTH SCORE
  -- Formula: 50% Performance + 25% Observability + 25% Pipeline Robustness
  (r.performance_score * 0.50) + 
  (COALESCE(o.observability_score, 0.0) * 0.25) + 
  (100.0 * 0.25) AS composite_service_health_score

FROM `${hub_project_id}.${dataset_id}.service_performance_scores` r
LEFT JOIN `${hub_project_id}.${dataset_id}.observability_scores` o
ON r.service_name = o.service_name

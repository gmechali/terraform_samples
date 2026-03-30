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
  r.error_5xx_requests,
  r.error_4xx_requests,
  r.total_errors,
  r.p50_target_ms,
  r.p95_target_ms,
  r.performance_score AS cat1_performance_score,
  
  -- Category 3: Observability Score
  -- We COALESCE to 0.0 in case a service hasn't been added to the Google Sheet yet
  COALESCE(o.observability_score, 0.0) AS cat3_observability_score,
  
  -- Category 2: Pipeline Robustness Score & Components
  -- We dynamically inject the Survey-Sourced Feature Flag score back into the final Pipeline calculation!
  IF(
    REGEXP_CONTAINS(r.archetype, r"(?i)async|pipeline|cron|ingest"),
    COALESCE(p.pipeline_score, 0.0), 
    COALESCE(p.pipeline_score, 0.0) + (COALESCE(o.feature_flag_score, 0.0) * 0.1)
  ) AS cat2_pipeline_score,
  
  COALESCE(p.cadence_score, 0.0) AS pipeline_cadence_score,
  COALESCE(p.delivery_success_score, 0.0) AS pipeline_delivery_success_score,
  COALESCE(p.code_lead_time_score, 0.0) AS pipeline_code_lead_time_score,
  COALESCE(o.feature_flag_score, 0.0) AS pipeline_feature_flag_score,
  p.days_since_last_deploy,
  p.months_deployed_in_window,
  p.last_successful_deployment,
  p.total_deployments_in_window,
  
  -- FINAL COMPOSITE SERVICE HEALTH SCORE
  -- Formula: 50% Performance + 25% Observability + 25% Pipeline Robustness
  (r.performance_score * 0.50) + 
  (COALESCE(o.observability_score, 0.0) * 0.25) + 
  (
    IF(REGEXP_CONTAINS(r.archetype, r"(?i)async|pipeline|cron|ingest"),
       COALESCE(p.pipeline_score, 0.0),
       COALESCE(p.pipeline_score, 0.0) + (COALESCE(o.feature_flag_score, 0.0) * 0.1)
    )
  ) * 0.25 AS composite_service_health_score

FROM `${hub_project_id}.${dataset_id}.service_performance_scores` r
LEFT JOIN `${hub_project_id}.${dataset_id}.observability_scores` o
  ON r.service_name = o.service_name
LEFT JOIN `${hub_project_id}.${dataset_id}.pipeline_robustness_scores` p
  ON r.service_name = p.service_name

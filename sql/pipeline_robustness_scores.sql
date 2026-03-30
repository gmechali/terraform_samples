WITH base_metrics AS (
  SELECT
    r.service_name,
    r.archetype,
    
    -- Gather Cadence Score pieces
    MAX(IF(d.status IN ('SUCCESS', 'SUCCEEDED'), d.publish_time, NULL)) AS last_successful_deployment,
    COUNT(d.publish_time) AS total_deployments_in_window,
    
    -- Days since deploy defaults to 999 if never
    IFNULL(DATE_DIFF(CURRENT_DATE(), DATE(MAX(IF(d.status IN ('SUCCESS', 'SUCCEEDED'), d.publish_time, NULL))), DAY), 999) AS days_since_last_deploy,
    
    -- Unique successful deployment months
    COUNT(DISTINCT IF(d.status IN ('SUCCESS', 'SUCCEEDED'), EXTRACT(MONTH FROM d.publish_time), NULL)) AS months_deployed_in_window,
    
    -- Delivery Success Logic defaults to 0.0 if never deployed
    IFNULL((COUNTIF(d.status IN ('SUCCESS', 'SUCCEEDED')) / NULLIF(COUNT(d.publish_time), 0)) * 100.0, 0.0) AS raw_delivery_success,
    
    -- Cold Start Fix: The denominator scales linearly from 1 (March 2026) up to 6 months max
    LEAST(6, DATE_DIFF(CURRENT_DATE(), DATE '2026-03-01', MONTH) + 1) AS valid_months_denominator

  FROM `${hub_project_id}.${dataset_id}.service_performance_scores` r
  LEFT JOIN `${hub_project_id}.${dataset_id}.deployment_events_raw` d
    ON r.service_name = d.service_name
    AND DATE(d.publish_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
  GROUP BY 
    r.service_name, 
    r.archetype
)

SELECT
  service_name,
  last_successful_deployment,
  total_deployments_in_window,
  days_since_last_deploy,
  months_deployed_in_window,
  
  -- Calculated Delivery Success Score
  raw_delivery_success AS delivery_success_score,
  
  -- Calculated Deployment Cadence Score (> 30 days => 0)
  IF(
    days_since_last_deploy > 30, 
    0.0, 
    (months_deployed_in_window / valid_months_denominator) * 100.0
  ) AS cadence_score,

  -- Component Parts (Placeholders default to 0% to highlight missing integrations)
  0.0 AS code_lead_time_score,
  0.0 AS feature_flag_score,
  
  -- Final Pipeline Robustness Score based on Archetype
  -- Sync / API: 30% Success, 30% Cadence, 30% Lead Time, 10% Feature Flag
  -- Async: 30% Success, 40% Cadence, 30% Lead Time
  IF(
    REGEXP_CONTAINS(archetype, r"(?i)async|pipeline|cron|ingest"),
    (raw_delivery_success * 0.3) + 
    (IF(days_since_last_deploy > 30, 0.0, (months_deployed_in_window / valid_months_denominator) * 100.0) * 0.4) + 
    (0.0 * 0.3),
    
    (raw_delivery_success * 0.3) + 
    (IF(days_since_last_deploy > 30, 0.0, (months_deployed_in_window / valid_months_denominator) * 100.0) * 0.3) + 
    (0.0 * 0.3) + 
    (0.0 * 0.1)
  ) AS pipeline_score

FROM base_metrics

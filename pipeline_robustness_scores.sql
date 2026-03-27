SELECT
  r.service_name,
  
  -- Gather Cadence Score pieces (ONLY tracking successful logic)
  MAX(IF(d.status IN ('SUCCESS', 'SUCCEEDED'), d.publish_time, NULL)) AS last_successful_deployment,
  COUNT(d.publish_time) AS total_deployments_in_window,
  IFNULL(DATE_DIFF(CURRENT_DATE(), DATE(MAX(IF(d.status IN ('SUCCESS', 'SUCCEEDED'), d.publish_time, NULL))), DAY), 999) AS days_since_last_deploy,
  COUNT(DISTINCT IF(d.status IN ('SUCCESS', 'SUCCEEDED'), EXTRACT(MONTH FROM d.publish_time), NULL)) AS months_deployed_in_window,
  
  -- Deployment Cadence Logic: > 30 days => 0
  -- Cold Start Fix: The denominator scales linearly from 1 (March 2026) up to 6 months max.
  IF(
    IFNULL(DATE_DIFF(CURRENT_DATE(), DATE(MAX(IF(d.status IN ('SUCCESS', 'SUCCEEDED'), d.publish_time, NULL))), DAY), 999) > 30, 
    0.0, 
    (
      COUNT(DISTINCT IF(d.status IN ('SUCCESS', 'SUCCEEDED'), EXTRACT(MONTH FROM d.publish_time), NULL)) 
      / 
      LEAST(6, DATE_DIFF(CURRENT_DATE(), DATE '2026-03-01', MONTH) + 1)
    ) * 100.0
  ) AS cadence_score,

  -- Delivery Success Logic (Percentage of SUCCESS vs FAILURE) defaults to 0.0 if never deployed
  IFNULL((COUNTIF(d.status IN ('SUCCESS', 'SUCCEEDED')) / NULLIF(COUNT(d.publish_time), 0)) * 100.0, 0.0) AS delivery_success_score,
     
  -- Component Parts (Placeholders default to 0% to highlight missing integrations)
  0.0 AS code_lead_time_score,
  0.0 AS feature_flag_score,
  
  -- Final Pipeline Robustness Score based on Archetype
  -- Sync / API: 30% Success, 30% Cadence, 30% Lead Time, 10% Feature Flag
  -- Async: 30% Success, 40% Cadence, 30% Lead Time
  IF(
    REGEXP_CONTAINS(r.archetype, r"(?i)async|pipeline|cron|ingest"),
    (IFNULL((COUNTIF(d.status IN ('SUCCESS', 'SUCCEEDED')) / NULLIF(COUNT(d.publish_time), 0)) * 100.0, 0.0) * 0.3) + 
      (IF(IFNULL(DATE_DIFF(CURRENT_DATE(), DATE(MAX(IF(d.status IN ('SUCCESS', 'SUCCEEDED'), d.publish_time, NULL))), DAY), 999) > 30, 0.0, (COUNT(DISTINCT IF(d.status IN ('SUCCESS', 'SUCCEEDED'), EXTRACT(MONTH FROM d.publish_time), NULL)) / 6.0) * 100.0) * 0.4) + 
      (0.0 * 0.3),
    (IFNULL((COUNTIF(d.status IN ('SUCCESS', 'SUCCEEDED')) / NULLIF(COUNT(d.publish_time), 0)) * 100.0, 0.0) * 0.3) + 
      (IF(IFNULL(DATE_DIFF(CURRENT_DATE(), DATE(MAX(IF(d.status IN ('SUCCESS', 'SUCCEEDED'), d.publish_time, NULL))), DAY), 999) > 30, 0.0, (COUNT(DISTINCT IF(d.status IN ('SUCCESS', 'SUCCEEDED'), EXTRACT(MONTH FROM d.publish_time), NULL)) / 6.0) * 100.0) * 0.3) + 
      (0.0 * 0.3) + 
      (0.0 * 0.1)
  ) AS pipeline_score

FROM `${hub_project_id}.${dataset_id}.service_performance_scores` r
LEFT JOIN `${hub_project_id}.${dataset_id}.deployment_events_raw` d
  ON r.service_name = d.service_name
  AND DATE(d.publish_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
GROUP BY r.service_name, r.archetype

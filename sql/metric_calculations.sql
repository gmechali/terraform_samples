-- Phase 3: Metric Calculation (BigQuery SQL)
-- This logic translates the plain-text formulas in `designdoc.txt` into native SQL.
-- You can save this as a BigQuery View or run it via BigQuery Scheduled Queries to power your Looker dashboard.

WITH raw_performance AS (
  SELECT 
    service_name,
    archetype, -- 'sync' or 'async'
    availability_ratio, 
    latency_p50_ms,
    latency_p95_ms,
    -- Example fields joined from the Aggregated Log Sink
    COALESCE(error_log_count, 0) AS error_log_count,
    COALESCE(total_requests, 1) AS total_requests,
    -- Example fields joined from the Pub/Sub Deployment Events table
    COALESCE(pipeline_robustness_score, 100.0) AS pipeline_robustness_score,
    COALESCE(observability_score, 100.0) AS observability_score
  FROM `YOUR_PROJECT_ID.oncall_health.raw_metrics`
),

calculated_performance AS (
  SELECT
    service_name,
    archetype,
    
    -- 1. Availability Score (direct ratio to percentage)
    availability_ratio * 100 AS availability_score,
    
    -- 2. Latency Score (Assuming Target P95 is 500ms for Sync)
    SAFE_CAST(LEAST(1.0, (500.0 / NULLIF(latency_p95_ms, 0))) * 100 AS FLOAT64) AS latency_score,
    
    -- 3. Bounded Decay Log Health Score
    -- Formula: Score = max(0, 100 - (badLogsRatio * 1000))
    GREATEST(0.0, 100.0 - ((error_log_count / total_requests) * 1000.0)) AS log_health_score,
    
    pipeline_robustness_score,
    observability_score

  FROM raw_performance
),

weighted_service_health AS (
  SELECT
    service_name,
    archetype,
    
    -- Adjust internal weighting dynamically based on the datacommons-archetype label!
    CASE 
      WHEN archetype = 'sync' THEN 
        -- Sync Weights: 65% Availability, 25% Latency, 10% Log Health
        (availability_score * 0.65) + (latency_score * 0.25) + (log_health_score * 0.10)
        
      WHEN archetype = 'async' THEN 
        -- Async Weights: 30% Availability, 60% Freshness/Data SLA (hardcoded to 100 here as example), 10% Log Health
        (availability_score * 0.30) + (100.0 * 0.60) + (log_health_score * 0.10) 
        
      ELSE 0 
    END AS performance_pillar_score,
    
    pipeline_robustness_score,
    observability_score
    
  FROM calculated_performance
)

-- Output: The Final Service Health Composite Formula for Looker
-- Formula: Service Health = (Performance Score * 0.50) + (Pipeline Robustness Score * 0.25) + (Observability Score * 0.25)
SELECT
  service_name,
  archetype,
  
  -- Broken down by pillars for visualization
  performance_pillar_score,
  pipeline_robustness_score,
  observability_score,
  
  -- The Final Single Score
  (performance_pillar_score * 0.50) + (pipeline_robustness_score * 0.25) + (observability_score * 0.25) AS final_service_health_score

FROM weighted_service_health;

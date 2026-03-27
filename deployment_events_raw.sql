SELECT 
  publish_time,
  -- Extracts native Cloud Build status (SUCCESS, FAILURE, WORKING, TIMEOUT)
  JSON_EXTRACT_SCALAR(data, '$.status') AS status,
  -- Assuming you use a tag shaped like 'cloudrun::dc-dev'
  JSON_EXTRACT_SCALAR(data, '$.tags[0]') AS service_name
FROM `${hub_project_id}.${dataset_id}.cloud_builds_raw`

UNION ALL

SELECT 
  publish_time,
  -- Extracts native Cloud Deploy Action status (SUCCEEDED, FAILED)
  JSON_EXTRACT_SCALAR(data, '$.Action') AS status,
  
  -- Maps the pristine TargetId from Cloud Deploy dynamically.
  -- Notice the website targets fan out an ARRAY of two services (website AND its mixer)!
  service_name
FROM `${hub_project_id}.${dataset_id}.cloud_deploy_raw`,
UNNEST(
  CASE JSON_EXTRACT_SCALAR(data, '$.TargetId')
    WHEN 'website-dev' THEN ARRAY['endpoints::website-esp.endpoints.datcom-website-dev.cloud.goog', 'endpoints::mixer-esp.endpoints.datcom-website-dev.cloud.goog']
    WHEN 'website-autopush' THEN ARRAY['endpoints::website-esp.endpoints.datcom-website-autopush.cloud.goog', 'endpoints::mixer-esp.endpoints.datcom-website-autopush.cloud.goog']
    WHEN 'website-staging' THEN ARRAY['endpoints::website-esp.endpoints.datcom-website-staging.cloud.goog', 'endpoints::mixer-esp.endpoints.datcom-website-staging.cloud.goog']
    WHEN 'website-prod-central' THEN ARRAY['endpoints::website-esp.endpoints.datcom-website-prod.cloud.goog', 'endpoints::mixer-esp.endpoints.datcom-website-prod.cloud.goog']
    WHEN 'website-prod-west' THEN ARRAY['endpoints::website-esp.endpoints.datcom-website-prod.cloud.goog', 'endpoints::mixer-esp.endpoints.datcom-website-prod.cloud.goog']
    WHEN 'mixer-dev' THEN ARRAY['endpoints::dev.api.datacommons.org']
    WHEN 'mixer-autopush' THEN ARRAY['endpoints::autopush.api.datacommons.org']
    WHEN 'mixer-staging' THEN ARRAY['endpoints::staging.api.datacommons.org']
    WHEN 'mixer-prod' THEN ARRAY['endpoints::api.datacommons.org']
    ELSE ARRAY[CONCAT('endpoints::', JSON_EXTRACT_SCALAR(data, '$.TargetId'))]
  END
) AS service_name

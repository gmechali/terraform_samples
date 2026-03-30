SELECT 
  publish_time,
  -- Extracts native Cloud Build status (SUCCESS, FAILURE, WORKING, TIMEOUT)
  JSON_EXTRACT_SCALAR(data, '$.status') AS status,
  -- Assuming you use a tag shaped like 'cloudrun--dc-dev'
  REPLACE(JSON_EXTRACT_SCALAR(data, '$.tags[0]'), '::', '--') AS service_name,
  `${hub_project_id}.${dataset_id}.get_environment`(REPLACE(JSON_EXTRACT_SCALAR(data, '$.tags[0]'), '::', '--')) AS environment
FROM `${hub_project_id}.${dataset_id}.cloud_builds_raw`
WHERE IFNULL(JSON_EXTRACT_SCALAR(data, '$.buildTriggerId'), '') NOT LIKE 'cloud-deploy-project-%'
  AND IFNULL(JSON_EXTRACT_SCALAR(data, '$.tags[0]'), '') NOT LIKE 'cloud-deploy-%'
  AND JSON_EXTRACT_SCALAR(data, '$.status') IN ('SUCCESS', 'FAILURE', 'TIMEOUT')
UNION ALL

SELECT 
  publish_time,
  -- Extracts native Cloud Deploy Action status and normalizes it (Succeed -> SUCCEEDED)
  IF(JSON_EXTRACT_SCALAR(attributes, '$.Action') = 'Succeed', 'SUCCEEDED', UPPER(JSON_EXTRACT_SCALAR(attributes, '$.Action'))) AS status,
  
  -- Maps the pristine TargetId from Cloud Deploy dynamically.
  service_name,
  
  -- Inject Environment mapping explicitly for Looker Studio Page Filtering
  `${hub_project_id}.${dataset_id}.get_environment`(service_name) AS environment

FROM `${hub_project_id}.${dataset_id}.cloud_deploy_raw`,
UNNEST(
  CASE JSON_EXTRACT_SCALAR(attributes, '$.TargetId')
    WHEN 'website-dev' THEN ARRAY['endpoints--website-esp.endpoints.datcom-website-dev.cloud.goog', 'endpoints--mixer-esp.endpoints.datcom-website-dev.cloud.goog']
    WHEN 'website-autopush' THEN ARRAY['endpoints--website-esp.endpoints.datcom-website-autopush.cloud.goog', 'endpoints--mixer-esp.endpoints.datcom-website-autopush.cloud.goog']
    WHEN 'website-staging' THEN ARRAY['endpoints--website-esp.endpoints.datcom-website-staging.cloud.goog', 'endpoints--mixer-esp.endpoints.datcom-website-staging.cloud.goog']
    WHEN 'website-prod-central' THEN ARRAY['endpoints--website-esp.endpoints.datcom-website-prod.cloud.goog', 'endpoints--mixer-esp.endpoints.datcom-website-prod.cloud.goog']
    WHEN 'website-prod-west' THEN ARRAY['endpoints--website-esp.endpoints.datcom-website-prod.cloud.goog', 'endpoints--mixer-esp.endpoints.datcom-website-prod.cloud.goog']
    WHEN 'mixer-dev' THEN ARRAY['endpoints--dev.api.datacommons.org']
    WHEN 'mixer-autopush' THEN ARRAY['endpoints--autopush.api.datacommons.org']
    WHEN 'mixer-staging' THEN ARRAY['endpoints--staging.api.datacommons.org']
    WHEN 'mixer-prod' THEN ARRAY['endpoints--api.datacommons.org']
    ELSE ARRAY[CONCAT('endpoints--', JSON_EXTRACT_SCALAR(attributes, '$.TargetId'))]
  END
) AS service_name
WHERE JSON_EXTRACT_SCALAR(attributes, '$.ResourceType') = 'Rollout'
  AND UPPER(JSON_EXTRACT_SCALAR(attributes, '$.Action')) IN ('SUCCEED', 'FAILED')

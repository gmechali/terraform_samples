# Data Commons On-Call Health Audit

This repository contains the automated, GCP-native infrastructure required to collect, calculate, and store Service Health and On-call Fatigue metrics, as defined in the Data Commons On-Call Health Audit design doc.

## Architecture: The Hub-and-Spoke Model

Because Data Commons services span multiple GCP projects, this infrastructure uses a centralized **Hub-and-Spoke** model:
1. **Hub Project**: Hosts the central BigQuery dataset (`oncall_health`), the centralized Pub/Sub topic, and the daily Python metric scraper (Cloud Function).
2. **Spoke Projects**: All other GCP projects where your services live.
3. **Aggregated Log Sink**: Routes `WARNING`/`ERROR`/`CRITICAL` logs from all Spoke projects directly to the Hub's BigQuery dataset.
4. **Metrics Scope**: Allows the Hub project's Cloud Function to natively read Cloud Monitoring metrics (Latency, Availability) from all Spoke projects.

## Repository Structure

- `backend.tf`: Configures the GCS remote state bucket.
- `providers.tf`: Configures the Google Cloud Terraform providers.
- `variables.tf`: Defines required inputs (Hub Project ID, Spoke Project IDs, Org/Folder IDs).
- `main.tf`: Provisions the central BigQuery dataset, Aggregated Log Sinks, Metrics Scope, and Pub/Sub topic.
- `function_deployment.tf`: Packages and deploys the ingestion Python script as a Cloud Function triggered daily by Cloud Scheduler.
- `ingestion/`: Contains the Python code (`main.py` & `requirements.txt`) that queries the Cloud Monitoring API for latency and availability metrics.
- `metric_calculations.sql`: The BigQuery SQL logic that calculates the Bounded Decay Log Health score and the final composite Service Health Score.

## How to Deploy

### 1. Configure Terraform State
Open `backend.tf` and replace `"YOUR_TERRAFORM_STATE_BUCKET"` with an actual GCS bucket name where you want to store your Terraform state.

### 2. Set Your Variables
Create a `terraform.tfvars` file in the root of this directory and populate the variables defined in `variables.tf`:
```hcl
hub_project_id    = "your-central-monitoring-project"
spoke_project_ids = ["data-commons-prod", "data-commons-dev"]

# You must provide EITHER an organization_id OR a folder_id for the Aggregated Log Sink
organization_id   = "1234567890" 
# folder_id       = "0987654321" 
```

### 3. Deploy the Infrastructure
Run the standard Terraform workflow to provision the Base Infrastructure and deployment pipeline.
```bash
terraform init
terraform plan
terraform apply
```
**Note**: The BigQuery dataset is configured with `delete_contents_on_destroy = true` for easy testing. If moving to production, you may want to remove this line from `main.tf`.

### 4. Create the BigQuery View
Once the Terraform runs successfully, go to the BigQuery UI in the GCP Console for your Hub project.
1. Copy the contents of `metric_calculations.sql`.
2. Update the `YOUR_PROJECT_ID` placeholder inside the `FROM` clause.
3. Run the query and save the results as a new **View** (e.g., `final_service_health_scores`) inside the `oncall_health` dataset.

### 5. Hook up Looker
Point your Looker dashboard directly to the `final_service_health_scores` view in BigQuery. Looker will now reflect automated, daily health scores for all your labeled (`datacommons-service`) GCP resources!

## Remaining Steps & Placeholders
While the core pipeline is fully operational for GKE Cloud Deploy targets, there are a few remaining integrations required to complete the complete DORA metrics scorecard.

### 1. Update Cloud Build Tags
For services that deploy natively through Cloud Build (like Cloud Run or Cloud Functions), you must explicitly define a custom tag in the source repository's `cloudbuild.yaml` so the BigQuery Log Sink can properly attribute the deploy event to the correct performance scorecard.

Add a `tags` array to your Cloud Build configuration matching your desired service name (e.g., `cloudrun::dc-dev`):
```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/my-project/my-image', '.']

# Add this to explicitly map the deployment to your Looker dashboard!
tags: ['cloudrun::dc-dev']
```

### 2. Implement Remaining Scoring Placeholders
The `pipeline_robustness_scores.sql` materialized view currently hardcodes two wildcard DORA metrics to `0.0` because their data sources have not yet been integrated into the Hub project. These act as placeholders in your Looker dashboard until you build the telemetry:

1. **Code Lead Time Score (`code_lead_time_score`)**: Will require integrating GitHub/Gerrit commit timestamps against Cloud Build completion timestamps to measure the velocity of code landing in production.
2. **Feature Flag Score (`feature_flag_score`)**: Will require integrating internal Data Commons feature flag telemetry (e.g., the JSON config files) to grade services on their safe progressive-rollout compliance.

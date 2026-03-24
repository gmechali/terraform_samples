terraform {
  backend "gcs" {
    # Replace with your actual GCS bucket name for state
    bucket = "gmechali_tf_state_oncallhealth"
    prefix = "gmechali_health_audit/state"
  }
}

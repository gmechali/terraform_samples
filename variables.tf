variable "hub_project_id" {
  description = "The central Hub project ID where metrics will be stored"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "spoke_project_ids" {
  description = "List of Spoke project IDs to collect metrics and logs from"
  type        = list(string)
  default     = []
}

variable "organization_id" {
  description = "Organization ID for the aggregated log sink (leave empty if using folder_id)"
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Folder ID for the aggregated log sink (leave empty if using organization_id)"
  type        = string
  default     = ""
}

variable "observability_sheet_url" {
  description = "The Google Sheets URL for the Category 3 Observability survey answers"
  type        = string
  default     = ""
}

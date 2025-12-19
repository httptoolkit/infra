variable "scw_access_key" {
  description = "Scaleway Access Key"
  type        = string
  sensitive   = true
}

variable "scw_secret_key" {
  description = "Scaleway Secret Key"
  type        = string
  sensitive   = true
}

variable "project_id" {
  type        = string
  description = "Scaleway Project ID"
}

variable "region" {
  type        = string
  default     = "fr-par"
  description = "Default region for resources"
}

variable "primary_zone" {
  type        = string
  default     = "fr-par-1"
  description = "Default zone for zonal resources"
}

variable "secondary_zone" {
  type        = string
  default     = "fr-par-2"
  description = "Secondary/failover zone for zonal resources"
}
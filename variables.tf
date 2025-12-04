variable "project_id" {
  type        = string
  description = "Scaleway Project ID"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL user password"
}

variable "region" {
  type        = string
  default     = "fr-par"
  description = "Default region for resources"
}

variable "zone" {
  type        = string
  default     = "fr-par-1"
  description = "Default zone for zonal resources"
}
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

variable "zone" {
  type        = string
  default     = "fr-par-1"
  description = "Default zone for zonal resources"
}

variable "httptoolk_it_tls_cert" {
  description = "PEM-encoded TLS certificate for *.e.httptoolk.it"
  type        = string
  sensitive   = true
}

variable "httptoolk_it_tls_key" {
  description = "PEM-encoded TLS private key for *.e.httptoolk.it"
  type        = string
  sensitive   = true
}
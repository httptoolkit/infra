variable "name" {
  description = "The name of the project/namespace"
  type        = string
}

variable "crd_reader_role_name" {
  description = "Name of the global ClusterRole that grants CRD read permissions"
  type        = string
}
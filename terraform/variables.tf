variable "folder_id" {
  type = string
}

variable "service_account_id" {
  type = string
}

variable "observer_service_account_id" {
  description = "Runtime identity for discovery and snapshot-schedule reconciliation."
  type        = string
}

variable "prefix" {
  type    = string
  default = "netology-course"
}

variable "zones" {
  type    = list(string)
  default = ["ru-central1-a", "ru-central1-d"]
  validation {
    condition     = length(distinct(var.zones)) == 2
    error_message = "Exactly two different availability zones are required."
  }
}

variable "ssh_public_key" {
  type = string
}

variable "admin_cidrs" {
  type = list(string)
}

variable "source_url" {
  type    = string
  default = "https://github.com/lobasov77777-debug/fops-sysadm-diplom.git"
}

variable "source_ref" {
  type = string
}

variable "elastic_password" {
  type      = string
  sensitive = true
}

variable "filebeat_password" {
  type      = string
  sensitive = true
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "enable_https" {
  description = "Enable after Certificate Manager reports ISSUED."
  type        = bool
  default     = false
}

variable "postgres_version" {
  type    = string
  default = "16"
}

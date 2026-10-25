variable "name" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "engine_version" {
  type    = string
  default = "8.0"
}

variable "allocated_storage" {
  description = "GB. 20 is the free tier limit"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling. null disables autoscaling (keeps you inside free tier)"
  type        = number
  default     = null
}

variable "storage_type" {
  type    = string
  default = "gp2"
}

variable "multi_az" {
  description = "Standby in a second AZ for failover (not free tier)"
  type        = bool
  default     = false
}

variable "create_read_replica" {
  description = "Create a read replica. Counts as a second instance against the free tier hours"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Must be >= 1 for read replicas. Free tier accounts are limited to 1 day"
  type        = number
  default     = 1
}

variable "production_safeguards" {
  description = "Deletion protection and a final snapshot (prod)"
  type        = bool
  default     = false
}

variable "recovery_window_days" {
  description = "Secrets Manager recovery window. 0 = delete immediately (dev)"
  type        = number
  default     = 0
}

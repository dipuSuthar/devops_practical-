variable "name" {
  type = string
}

variable "alarm_email" {
  description = "Email for alarm notifications (empty = topic only)"
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "replica_identifier" {
  type    = string
  default = ""
}

variable "create_replica_alarm" {
  type    = bool
  default = false
}

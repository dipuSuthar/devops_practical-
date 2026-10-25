variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "devops-task"
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "domain_name" {
  description = "Existing Route53 public hosted zone, e.g. example.com"
  type        = string
}

variable "app_subdomain" {
  type = string
}

variable "releases_bucket" {
  description = "S3 bucket (created by bootstrap/) holding app release zips"
  type        = string
}

variable "alarm_email" {
  type    = string
  default = ""
}

# ---- compute ----
variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 4
}

variable "standby_min" {
  type    = number
  default = 1
}

# ---- database ----
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_create_read_replica" {
  type    = bool
  default = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 1
}

# ---- blue/green controls (set by scripts/deploy.sh) ----
variable "active_color" {
  type    = string
  default = "blue"
  validation {
    condition     = contains(["blue", "green"], var.active_color)
    error_message = "active_color must be blue or green."
  }
}

variable "blue_version" {
  type    = string
  default = ""
}

variable "green_version" {
  type    = string
  default = ""
}

variable "idle_full_capacity" {
  type    = bool
  default = false
}

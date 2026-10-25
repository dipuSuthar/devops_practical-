variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_sg_id" {
  type = string
}

variable "instance_profile_arn" {
  type = string
}

variable "target_group_arns" {
  description = "Map of colour => target group ARN"
  type        = map(string)
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min" {
  description = "Instances in the ACTIVE colour"
  type        = number
  default     = 2
}

variable "asg_max" {
  type    = number
  default = 4
}

variable "standby_min" {
  description = "Instances kept warm in the IDLE colour for instant rollback"
  type        = number
  default     = 1
}

variable "active_color" {
  type = string
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

variable "releases_bucket" {
  type = string
}

variable "secret_arn" {
  type = string
}

variable "app_bucket_id" {
  type = string
}

variable "app_port" {
  type    = number
  default = 3000
}

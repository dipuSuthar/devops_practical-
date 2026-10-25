variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "logs_bucket_id" {
  type = string
}

variable "domain_name" {
  description = "Existing Route53 public hosted zone, e.g. example.com"
  type        = string
}

variable "subdomain" {
  type = string
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "colors" {
  type    = list(string)
  default = ["blue", "green"]
}

variable "active_color" {
  type = string
}

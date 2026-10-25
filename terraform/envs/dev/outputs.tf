output "app_url" {
  value = "https://${module.alb.fqdn}"
}

output "active_color" {
  value = var.active_color
}

output "blue_version" {
  value = var.blue_version
}

output "green_version" {
  value = var.green_version
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "db_primary_endpoint" {
  value = module.database.primary_endpoint
}

output "db_replica_endpoint" {
  value = module.database.replica_endpoint
}

output "db_secret_arn" {
  value = module.database.secret_arn
}

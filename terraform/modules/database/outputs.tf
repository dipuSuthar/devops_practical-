output "secret_arn" {
  description = "Secret ARN; depends on the DB (and replica) being created"
  value       = aws_secretsmanager_secret_version.db.arn
}

output "primary_endpoint" {
  value = aws_db_instance.primary.address
}

output "replica_endpoint" {
  value = var.create_read_replica ? aws_db_instance.replica[0].address : ""
}

output "primary_identifier" {
  value = aws_db_instance.primary.identifier
}

output "replica_identifier" {
  value = var.create_read_replica ? aws_db_instance.replica[0].identifier : ""
}

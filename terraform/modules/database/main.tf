resource "random_password" "db" {
  length  = 24
  special = false # avoids characters that break connection strings
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.db_subnet_ids
}

# Force TLS for every client connection
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-mysql-"
  family      = "mysql8.0"
  parameter {
    name  = "require_secure_transport"
    value = "1"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# ---------- Primary (writer) ----------
resource "aws_db_instance" "primary" {
  identifier                 = "${var.name}-mysql-primary"
  engine                     = "mysql"
  engine_version             = var.engine_version
  instance_class             = var.instance_class
  allocated_storage          = var.allocated_storage
  max_allocated_storage      = var.max_allocated_storage
  storage_type               = var.storage_type
  storage_encrypted          = true
  db_name                    = "appdb"
  username                   = "appadmin"
  password                   = random_password.db.result
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [var.security_group_id]
  parameter_group_name       = aws_db_parameter_group.this.name
  publicly_accessible        = false
  multi_az                   = var.multi_az
  backup_retention_period    = var.backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  deletion_protection        = var.production_safeguards
  skip_final_snapshot        = !var.production_safeguards
  final_snapshot_identifier  = var.production_safeguards ? "${var.name}-mysql-final" : null
}

# ---------- Read replica (reader) ----------
# Inherits engine, storage, encryption and subnet group from the primary.
resource "aws_db_instance" "replica" {
  count                      = var.create_read_replica ? 1 : 0
  identifier                 = "${var.name}-mysql-replica"
  replicate_source_db        = aws_db_instance.primary.identifier
  instance_class             = var.instance_class
  vpc_security_group_ids     = [var.security_group_id]
  parameter_group_name       = aws_db_parameter_group.this.name
  publicly_accessible        = false
  multi_az                   = false
  backup_retention_period    = 0
  auto_minor_version_upgrade = true
  skip_final_snapshot        = true
}

# ---------- Credentials: written once, read by the app at runtime ----------
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name}/db-credentials"
  recovery_window_in_days = var.recovery_window_days
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username    = aws_db_instance.primary.username
    password    = random_password.db.result
    host        = aws_db_instance.primary.address
    reader_host = var.create_read_replica ? aws_db_instance.replica[0].address : aws_db_instance.primary.address
    port        = 3306
    dbname      = aws_db_instance.primary.db_name
  })
}

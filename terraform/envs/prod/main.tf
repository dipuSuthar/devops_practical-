locals {
  name = "${var.project}-${var.environment}"
  prod = var.environment == "prod"
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "security" {
  source = "../../modules/security"
  name   = local.name
  vpc_id = module.network.vpc_id
}

module "storage" {
  source        = "../../modules/storage"
  name          = local.name
  force_destroy = !local.prod
}

module "database" {
  source                = "../../modules/database"
  name                  = local.name
  db_subnet_ids         = module.network.db_subnet_ids
  security_group_id     = module.security.db_sg_id
  instance_class        = var.db_instance_class
  multi_az              = var.db_multi_az
  create_read_replica   = var.db_create_read_replica
  backup_retention_days = var.db_backup_retention_days
  production_safeguards = local.prod
  recovery_window_days  = local.prod ? 7 : 0
  max_allocated_storage = local.prod ? 100 : null
}

module "iam" {
  source          = "../../modules/iam"
  name            = local.name
  secret_arn      = module.database.secret_arn
  releases_bucket = var.releases_bucket
  app_bucket_arn  = "arn:aws:s3:::${module.storage.app_bucket_id}"
}

module "alb" {
  source            = "../../modules/alb"
  name              = local.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  logs_bucket_id    = module.storage.logs_bucket_id
  domain_name       = var.domain_name
  subdomain         = var.app_subdomain
  active_color      = var.active_color
  depends_on        = [module.storage] # log bucket policy must exist before the ALB writes logs
}

module "compute" {
  source               = "../../modules/compute"
  name                 = local.name
  region               = var.region
  private_subnet_ids   = module.network.private_subnet_ids
  app_sg_id            = module.security.app_sg_id
  instance_profile_arn = module.iam.instance_profile_arn
  target_group_arns    = module.alb.target_group_arns
  instance_type        = var.instance_type
  asg_min              = var.asg_min
  asg_max              = var.asg_max
  standby_min          = var.standby_min
  active_color         = var.active_color
  blue_version         = var.blue_version
  green_version        = var.green_version
  idle_full_capacity   = var.idle_full_capacity
  releases_bucket      = var.releases_bucket
  secret_arn           = module.database.secret_arn
  app_bucket_id        = module.storage.app_bucket_id
}

module "monitoring" {
  source               = "../../modules/monitoring"
  name                 = local.name
  alarm_email          = var.alarm_email
  alb_arn_suffix       = module.alb.arn_suffix
  db_identifier        = module.database.primary_identifier
  replica_identifier   = module.database.replica_identifier
  create_replica_alarm = var.db_create_read_replica
}

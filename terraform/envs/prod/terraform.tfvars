# Production settings. Not free tier: Multi-AZ primary, NAT per AZ, bigger standby.
environment   = "prod"
app_subdomain = "app"

instance_type = "t3.micro"
asg_min       = 2
asg_max       = 4
standby_min   = 2

db_instance_class        = "db.t3.micro"
db_multi_az              = true
db_create_read_replica   = true
db_backup_retention_days = 7

single_nat_gateway = false

# Non-secret settings for this environment. domain_name and releases_bucket
# come from TF_VAR_* (GitHub repository variables).
environment   = "dev"
app_subdomain = "dev"

instance_type = "t3.micro"
asg_min       = 2
asg_max       = 3
standby_min   = 1

db_instance_class        = "db.t3.micro"
db_multi_az              = false
db_create_read_replica   = true # set false to stay fully inside the free tier
db_backup_retention_days = 1

single_nat_gateway = true

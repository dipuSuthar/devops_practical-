locals {
  colors   = ["blue", "green"]
  versions = { blue = var.blue_version, green = var.green_version }

  # Active colour runs at full size. Idle colour stays warm (standby_min) for instant
  # rollback, or runs full size while a new release is being validated. No version = off.
  capacity = {
    for c in local.colors : c => local.versions[c] == "" ? 0 : (c == var.active_color || var.idle_full_capacity ? var.asg_min : var.standby_min)
  }
  max_capacity = {
    for c in local.colors : c => local.versions[c] == "" ? 0 : var.asg_max
  }
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "this" {
  for_each               = toset(local.colors)
  name_prefix            = "${var.name}-${each.key}-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 10
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    releases_bucket = var.releases_bucket
    release_key     = "releases/app-${local.versions[each.key]}.zip"
    region          = var.region
    secret_arn      = var.secret_arn
    app_bucket      = var.app_bucket_id
    app_port        = var.app_port
    color           = each.key
    version         = local.versions[each.key]
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-${each.key}", Color = each.key }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The release version is part of the ASG name, so a new release creates a brand-new
# ASG (create_before_destroy) and Terraform waits until its instances are healthy
# in the target group (wait_for_elb_capacity) before the old one is removed.
resource "aws_autoscaling_group" "this" {
  for_each                  = toset(local.colors)
  name                      = "${var.name}-${each.key}-${local.versions[each.key] == "" ? "none" : local.versions[each.key]}"
  min_size                  = local.capacity[each.key]
  max_size                  = local.max_capacity[each.key]
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [var.target_group_arns[each.key]]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  wait_for_elb_capacity     = local.capacity[each.key] > 0 ? local.capacity[each.key] : null
  wait_for_capacity_timeout = "20m"

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = aws_launch_template.this[each.key].latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-${each.key}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Color"
    value               = each.key
    propagate_at_launch = true
  }
  tag {
    key                 = "Release"
    value               = local.versions[each.key] == "" ? "none" : local.versions[each.key]
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  for_each               = toset(local.colors)
  name                   = "${var.name}-${each.key}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.this[each.key].name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}

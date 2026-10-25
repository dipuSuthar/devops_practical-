output "asg_names" {
  value = { for k, v in aws_autoscaling_group.this : k => v.name }
}

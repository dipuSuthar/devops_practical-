output "fqdn" {
  value = local.fqdn
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arns" {
  value = { for k, v in aws_lb_target_group.this : k => v.arn }
}

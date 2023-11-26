output "zone_id" {
  value       = local.zone_id
  description = "Zone ID of the Route53 Hosted Zone"
}

output "zone_name" {
  value       = local.zone_name
  description = "DNS Name for the Route53 Hosted Zone"
}

output "zone_arn" {
  value       = local.zone_arn
  description = "ARN for the Route53 Hosted Zone"
}

output "zone_name_servers" {
  value       = local.zone_name_servers
  description = "Name Servers for the Route53 Hosted Zone"
}

output "record_id" {
  value       = aws_route53_record.this.id
  description = "ID of the DNS Record"
}

output "record_name" {
  value       = aws_route53_record.this.name
  description = "DNS Name of the Route53 Record"
}

output "record_control_policy_arn" {
  value       = aws_iam_policy.this.arn
  description = "IAM Policy that allows modification of the DNS Record (and Hosted Zone information)"
}

output "query_log_group_arn" {
  value       = var.configure_query_log ? (var.create_query_log_group ? aws_cloudwatch_log_group.query[0].arn : var.query_log_group_arn) : ""
  description = "ARN of the CloudWatch Log Group that will receive the DNS Query logs"
}

output "query_log_group_filter_patten" {
  value       = "\"${aws_route53_record.this.name}\""
  description = "A CloudWatch filter pattern that will match this DNS record only"
}
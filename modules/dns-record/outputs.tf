output "record_control_policy_arn" {
  value = aws_iam_policy.this.arn
}

output "record_id" {
  value = aws_route53_record.this.id
}

output "record_name" {
  value = aws_route53_record.this.name
}

output "query_log_group_arn" {
  value = aws_cloudwatch_log_group.query.arn
}

output "query_log_group_filter_patten" {
  value = "\"${aws_route53_record.this.name}\""
}
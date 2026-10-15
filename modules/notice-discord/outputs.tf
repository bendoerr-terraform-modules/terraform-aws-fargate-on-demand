output "notice_role_name" {
  value       = aws_iam_role.notice_role.name
  description = "TODO"
}

output "notice_role_arn" {
  value       = aws_iam_role.notice_role.arn
  description = "TODO"
}

output "errors_alarm_arn" {
  value       = one(aws_cloudwatch_metric_alarm.errors[*].arn)
  description = "ARN of the delivery-failure alarm, or null when alarm_topic_arns is empty."
}

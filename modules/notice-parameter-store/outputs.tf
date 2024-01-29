output "notice_role_name" {
  value       = aws_iam_role.notice_role.name
  description = "TODO"
}

output "notice_role_arn" {
  value       = aws_iam_role.notice_role.arn
  description = "TODO"
}

output "parameter_name" {
  value       = aws_ssm_parameter.state.name
  description = "TODO"
}

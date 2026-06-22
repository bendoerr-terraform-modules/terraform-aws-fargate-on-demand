output "notice_role_name" {
  value       = aws_iam_role.notice_role.name
  description = "Name of the IAM role assumed by the notice-github Lambda."
}

output "notice_role_arn" {
  value       = aws_iam_role.notice_role.arn
  description = "ARN of the IAM role assumed by the notice-github Lambda."
}

output "notice_function_name" {
  value       = aws_lambda_function.notice.function_name
  description = "Name of the notice-github Lambda function."
}

output "notice_function_arn" {
  value       = aws_lambda_function.notice.arn
  description = "ARN of the notice-github Lambda function."
}

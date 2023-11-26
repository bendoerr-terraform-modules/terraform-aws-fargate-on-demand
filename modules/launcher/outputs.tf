output "lambda_id" {
  value       = aws_lambda_function.launcher.id
  description = "AWS Lambda ID of the launcher function"
}

output "lambda_arn" {
  value       = aws_lambda_function.launcher.arn
  description = "AWS Lambda ARN of the launcher function"
}

output "lambda_log_group_id" {
  value       = aws_cloudwatch_log_group.launcher.id
  description = "The CloudWatch Log Group ID for the logs from the AWS Lambda function"
}

output "lambda_role_id" {
  value       = aws_iam_role.launcher_role.id
  description = "The IAM Role of the AWS Lambda launcher function"
}

output "lambda_role_arn" {
  value       = aws_iam_role.launcher_role.arn
  description = "The IAM Role of the AWS Lambda launcher function"
}

output "record_control_policy_arn" {
  value = aws_iam_policy.this.arn
}

output "record_id" {
  value = aws_route53_record.this.id
}

output "record_name" {
  value = aws_route53_record.this.name
}

output "esc_cluster_name" {
  value = aws_ecs_cluster.svc.name
}

output "esc_cluster_arn" {
  value = aws_ecs_cluster.svc.arn
}

output "esc_service_name" {
  value = aws_ecs_service.svc.name
}

output "svc_control_policy_arn" {
  description = ""
  value       = aws_iam_policy.ecs_control.arn
}

output "events_topic_arn" {
  value = aws_sns_topic.notifications.arn
}
module "notify" {
  source  = "../.."
  context = module.context.shared

  event_topic_arn = aws_sns_topic.events.arn
}

output "sns_topic" {
  value = aws_sns_topic.events.arn
}

output "parameter_name" {
  value = module.notify.parameter_name
}

module "label_alarms" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = var.context
  name    = "alarms"
}

# Separate from aws_sns_topic.notifications: the notice Lambdas parse custodian
# lifecycle JSON off that topic and would fail on CloudWatch alarm payloads.
resource "aws_sns_topic" "alarms" {
  name              = module.label_alarms.id
  tags              = module.label_alarms.tags
  kms_master_key_id = var.sns_kms_key_id
}

resource "aws_sns_topic_subscription" "alarms_email" {
  for_each = toset(var.alarm_email_endpoints)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "max_runtime" {
  alarm_name        = module.label_alarms.id
  tags              = module.label_alarms.tags
  alarm_description = "Fires when the service has emitted CPUUtilization datapoints for ${var.max_runtime_hours} consecutive hour(s), i.e. it has been running continuously past max_runtime_hours."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.svc.name
    ServiceName = aws_ecs_service.svc.name
  }

  statistic           = "SampleCount"
  period              = 3600
  evaluation_periods  = var.max_runtime_hours
  datapoints_to_alarm = var.max_runtime_hours
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
}

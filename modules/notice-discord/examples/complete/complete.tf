variable "discord_bot_auth_token" {
  type = string
}

variable "discord_channel_id" {
  type = string
}

module "label_topic" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = module.context.shared
  name    = "ntc-dscrd-topic"
}

# Intentionally unencrypted, matching notice-github's example topic. This topic
# receives ECS task-state events; in real use a service principal (e.g.
# EventBridge) publishes, and such principals cannot use the AWS-managed
# alias/aws/sns key -- its key policy can't be granted to them -- so SSE with the
# managed key would silently break delivery. The org doesn't use CMKs, so
# AWS-0095 is suppressed rather than satisfied.
# trivy:ignore:AVD-AWS-0095
resource "aws_sns_topic" "events" {
  name = module.label_topic.id
  tags = module.label_topic.tags
}

module "label_alarms" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = module.context.shared
  name    = "ntc-dscrd-alarms"
}

# Same SSE reasoning as the events topic above: cloudwatch.amazonaws.com cannot use the
# AWS-managed alias/aws/sns key, and the org does not use CMKs.
# trivy:ignore:AVD-AWS-0095
resource "aws_sns_topic" "alarms" {
  name = module.label_alarms.id
  tags = module.label_alarms.tags
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "alarms" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms.json
}

module "notify" {
  source  = "../.."
  context = module.context.shared

  discord_bot_auth_token = var.discord_bot_auth_token
  discord_channel_id     = var.discord_channel_id
  event_topic_arn        = aws_sns_topic.events.arn
  notify_app_name        = "Terratest - Complete"
  notify_app_url         = "https://example.com"
  alarm_topic_arns       = [aws_sns_topic.alarms.arn]
}

output "sns_topic" {
  value = aws_sns_topic.events.arn
}

output "errors_alarm_arn" {
  value = module.notify.errors_alarm_arn
}

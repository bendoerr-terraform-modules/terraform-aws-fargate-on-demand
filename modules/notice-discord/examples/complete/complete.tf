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

module "notify" {
  source  = "../.."
  context = module.context.shared

  discord_bot_auth_token = var.discord_bot_auth_token
  discord_channel_id     = var.discord_channel_id
  event_topic_arn        = aws_sns_topic.events.arn
  notify_app_name        = "Terratest - Complete"
  notify_app_url         = "https://example.com"
}

output "sns_topic" {
  value = aws_sns_topic.events.arn
}
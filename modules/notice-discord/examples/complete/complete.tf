variable "discord_bot_auth_token" {
  type = string
}

variable "discord_channel_id" {
  type = string
}

module "label_topic" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = module.context.shared
  name    = "ntc-dscrd-topic"
}

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
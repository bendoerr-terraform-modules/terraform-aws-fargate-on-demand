variable "github_token" {
  type      = string
  sensitive = true
}

variable "github_repo" {
  type = string
}

module "label_topic" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = module.context.shared
  name    = "ntc-gh-topic"
}

resource "aws_sns_topic" "events" {
  name = module.label_topic.id
  tags = module.label_topic.tags
  # AWS-managed encryption (no CMK, per house style); satisfies AWS-0095.
  kms_master_key_id = "alias/aws/sns"
}

module "notify" {
  source  = "../.."
  context = module.context.shared

  github_token    = var.github_token
  github_repo     = var.github_repo
  event_topic_arn = aws_sns_topic.events.arn
  notify_app_name = "Terratest - Complete"
  notify_app_url  = "https://example.com"
}

output "sns_topic" {
  value = aws_sns_topic.events.arn
}

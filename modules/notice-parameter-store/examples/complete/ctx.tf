variable "namespace" {
  type = string
}

module "context" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.5.2"
  namespace   = var.namespace
  environment = "test"
  role        = "complete"
  region      = "us-east-1"
  project     = "notice-parameter-store"
}

module "label_topic" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = module.context.shared
  name    = "ntc-topic"
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

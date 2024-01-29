variable "namespace" {
  type = string
}

module "context" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.4.0"
  namespace   = var.namespace
  environment = "test"
  role        = "complete"
  region      = "us-east-1"
  project     = "notice-parameter-store"
}

module "label_topic" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.1"
  context = module.context.shared
  name    = "ntc-topic"
}

resource "aws_sns_topic" "events" {
  name = module.label_topic.id
  tags = module.label_topic.tags
}

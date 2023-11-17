variable "namespace" {
  type = string
}

module "context" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.4.0"
  namespace   = var.namespace
  environment = "test"
  role        = "complete"
  region      = "us-east-1"
  project     = "notice-discord"
}
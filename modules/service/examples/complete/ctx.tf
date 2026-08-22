variable "namespace" {
  type = string
}

module "context" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.5.2"
  namespace   = var.namespace
  environment = "testing"
  role        = "development"
  region      = "us-east-1"
  project     = "service"
}

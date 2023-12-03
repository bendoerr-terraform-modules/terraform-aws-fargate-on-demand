module "label" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "svc"
}

module "label_wd" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "svc-wtchdg"

}

module "label_data" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "svc-data"
}

module "label_ctl" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "svc-ctl"
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "svc" {
  name              = "/aws/ecs/${module.label.id}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_id
}
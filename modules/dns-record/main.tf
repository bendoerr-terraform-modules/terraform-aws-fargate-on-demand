data "aws_caller_identity" "this" {}

module "label" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.5.0"
  context = var.context
  name    = "rcrd"
}

module "label_ctl" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.5.0"
  context = var.context
  name    = "rcrd-ctl"
}

module "label_logs" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.5.0"
  context = var.context
  name    = "rcrd-logs"
}

locals {
  aws_route53_zone          = var.create_zone ? aws_route53_zone.this[0] : data.aws_route53_zone.this[0]
  zone_id                   = local.aws_route53_zone.zone_id
  zone_arn                  = local.aws_route53_zone.arn
  zone_name                 = local.aws_route53_zone.name
  zone_name_servers         = local.aws_route53_zone.name_servers
  create_log_group          = var.configure_query_log && var.create_query_log_group
  configure_resource_policy = var.configure_query_log && var.create_log_resource_policy
  query_log_group_arn       = local.create_log_group ? aws_cloudwatch_log_group.query[0].arn : var.query_log_group_arn
}